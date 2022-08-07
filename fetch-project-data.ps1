## Required Azure DevOps Token. Env variables:
# $env:DEVOPS_USER="username" # is SSO Office365 company email
# $env:DEVOPS_TOKEN="XXXXXXX" 
# $env:DEVOPS_BASEURL="https://dev.azure.com/ORGANIZATION"

$ErrorActionPreference = "Stop"

write-host "Username: $env:DEVOPS_USER"

if(-not ($env:DEVOPS_USER)) { throw "Missing DEVOPS_USER env variable." }
if(-not ($env:DEVOPS_TOKEN)) { throw "Missing DEVOPS_TOKEN env variable." }
if(-not ($env:DEVOPS_BASEURL)) { throw "Missing DEVOPS_BASEURL env variable." }

$baseUrl = $env:DEVOPS_BASEURL
write-host "Base URL: $baseUrl"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $env:DEVOPS_USER,$env:DEVOPS_TOKEN)))
$authHeader =  @{Authorization=("Basic {0}" -f $base64AuthInfo)}

write-host "Fetching projects."

$projects = Invoke-RestMethod "$baseUrl/_apis/projects?api-version=6.0" -Headers $authHeader

write-host "Found $($projects.count) projects."

$repositories = $projects.value | %{ 
    $projectName = $_.name
    $projectId = $_.id
    $projectData = Invoke-RestMethod "$baseUrl/$projectId/_apis/git/repositories?api-version=6.0" -Headers $authHeader
    write-host " - Found $($projectData.count) repositories in project $projectName."
    $projectData.value
}

write-host "Found $($repositories.Length) repositories in $($projects.count) projects."

$repositories | %{ 
    $repo = $_
    $repoId = [System.Guid]::Parse($repo.id).ToString("N") # remove "-" (not works in repo Id but is OK with project Id)
    $repoName = $repo.name
    $project = $repo.project
    $projectName = $project.name
    $projectId = $project.id
    $repo | Add-Member -NotePropertyName pathName -NotePropertyValue "$orgSlug/$projectName/$repoName"
    $repo | Add-Member -NotePropertyName sizeMB -NotePropertyValue ([System.Math]::Ceiling($_.size / 1024 / 1024))
    $refs = Invoke-RestMethod "$baseUrl/$projectId/_apis/git/repositories/$repoId/refs?`$top=1000&peelTags=true&api-version=6.0" -Headers $authHeader
    $repo | Add-Member -NotePropertyName refs -NotePropertyValue @($refs.value)
    $repo | Add-Member -NotePropertyName isEmpty -NotePropertyValue ($_.refs.Length -eq 0)
    write-host " - Found repo $($repo.pathName); size=$($repo.sizeMB)MB; refs=$($_.refs.Length)"
    $_.refs | %{
        $ref = $_
        $commitId = $ref.peeledObjectId
        if($commitId -eq $null) { $commitId = $ref.objectId }
        $ref | Add-Member -NotePropertyName commitId -NotePropertyValue $commitId
        write-host "  - Repo $($repo.pathName) - fetching details for ref $($ref.name): commitId=$commitId"
        $commit = Invoke-RestMethod "$baseUrl/$projectId/_apis/git/repositories/$repoId/commits/$($commitId)?changeCount=1&api-version=6.0" -Headers $authHeader
        $ref | Add-Member -NotePropertyName commit -NotePropertyValue $commit
        $ref | Add-Member -NotePropertyName isBranch -NotePropertyValue ($ref.name.StartsWith('refs/heads/'))
        $ref | Add-Member -NotePropertyName isTag -NotePropertyValue ($ref.name.StartsWith('refs/tags/'))
    }
    

    $defaultBranchRef = ($repo.refs | Where-Object -Property name -EQ $repo.defaultBranch | Select-Object -First 1)
    $_.refs | %{
        if($_.isBranch -eq $false)
        {
            $defaultBranchRelation = "not-branch"
        }
        elseif($defaultBranchRef -eq $null)
        {
            # no default branch (should not happen) - mark as no base merge commit is found
            $defaultBranchRelation = "other-tree"
        }
        elseif($_.commitId -eq $defaultBranchRef.commitId)
        {
            # same commit as default branch
            $defaultBranchRelation = "same-as-default"
        } else {
            # find merge base commit (newest commit in both branches)
            $mergeBaseResult = Invoke-RestMethod "$baseUrl/$projectId/_apis/git/repositories/$repoId/commits/$($_.commitId)/mergebases?otherCommitId=$($defaultBranchRef.commitId)&api-version=6.0" -Headers $authHeader
            if($mergeBaseResult.count -eq 1) {
                $mergeBaseCommitId = $mergeBaseResult.value[0].commitId
                
                if($mergeBaseCommitId -eq $_.commitId) {
                    # branch commit is newest base commit - fast-forward available from this branch to default branch (only commits behind)
                    $defaultBranchRelation = "fast-forwardable-to-default"
                } elseif ($mergeBaseCommitId -eq $defaultBranchRef.commitId)
                {
                    # default branch commit is newest base commit - fast-forward available from default branch to this branch (only commits ahead)
                    $defaultBranchRelation = "ahead-of-default"
                } else
                {
                    # there is some other base commit - there are both behind and ahead commits
                    $defaultBranchRelation = "needs-merge"
                }
            } else {
                # no base commit found - different trees
                $defaultBranchRelation = "other-tree"
            }

        }
        write-host "       - Default branch merge check $($_.name) : $defaultBranchRelation"
        $_ | Add-Member -NotePropertyName defaultBranchRelation -NotePropertyValue $defaultBranchRelation
    }
}


$repositories | ConvertTo-Json -Depth 99 | Out-File ./output/projects-data.json

write-host "All done."
