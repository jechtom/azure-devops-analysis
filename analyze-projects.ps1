param(
    [Parameter(Mandatory=$true)]$dataPath
)

$ErrorActionPreference = "Stop"

### Load

$data = get-content $dataPath | ConvertFrom-Json

### Precalculate

# add days count since last commit to repo and each ref (branch/tag)
$now = Get-Date
$data | %{
    $_.refs | %{
        $commitDate = [datetime]::Parse($_.commit.author.date)
        $_ | Add-Member -NotePropertyName lastCommitDaysAgo -NotePropertyValue ([System.Math]::Ceiling($now.Subtract($commitDate).TotalDays))
    }
    $min = ($_.refs | Measure-Object -Property lastCommitDaysAgo -Minimum).Minimum
    $_ | Add-Member -NotePropertyName lastCommitDaysAgo -NotePropertyValue $min
}

### Report

Write-Output "# Project and Repos Analysis"

Write-Output ""
Write-Output "Generated at: $(get-date)"
Write-Output "Generated with: https://github.com/jechtom/azure-devops-analysis"
Write-Output ""
Write-Output "[[_TOC_]]" # table of content (AzureDevOps Wiki)
Write-Output ""
Write-Output "## Projects and repos tree"
Write-Output '```'
$data | Select-Object @{ Name="projectName"; Expression={ $_.project.name }}, name, lastCommitDaysAgo, isEmpty, refs | Group-Object -Property projectName | Sort-Object -Property Name | %{ 
    Write-Output "- project: $($_.Name)"
    $_.Group | Sort-Object -Property name | %{
        if($_.isEmpty -eq $true) {
            Write-Output "  +- repo: $($_.name) - empty repo"
        } else {
            Write-Output "  +- repo: $($_.name) - last commit: $($_.lastCommitDaysAgo) days ago"
        }
    }
}
Write-Output '```'

Write-Output ""
Write-Output "## Empty repos"
Write-Output '```'
$data | Where-Object -Property isEmpty | Select-Object pathName | Sort-Object pathName | Format-Table
Write-Output '```'

$oldIsOlderThanDays = 60
Write-Output ""
Write-Output "## Repos by last activity (>$oldIsOlderThanDays days)"
Write-Output '```'
$data | Where {$_.lastCommitDaysAgo -cgt $oldIsOlderThanDays } | Select-Object pathName, lastCommitDaysAgo | Sort-Object lastCommitDaysAgo -Descending | Format-Table
Write-Output '```'

$largeRepoMB = 50
Write-Output ""
Write-Output "## Large Repos (>$($largeRepoMB)MB)"
Write-Output '```'
$data | Sort-Object -Descending -Property size | Select-Object pathName, sizeMB | Where-Object -Property sizeMB -CGT $largeRepoMB | Format-Table
Write-Output '```'

Write-Output ""
Write-Output "## Repos branches overview (non-empty repos)"
Write-Output '```'
$data | Where-Object -Property isEmpty -eq $false | Select-Object pathName, defaultBranch,
    @{ Name="Tags"; Expression={ @($_.refs | Where-Object -Property isTag).Count }},
    @{ Name="Branches"; Expression={ @($_.refs | Where-Object -Property isBranch).Count }},
    @{ Name="RefsTotal"; Expression={ $_.refs.Count }},
    @{ Name="BranchesSameAsDefault"; Expression={ @($_.refs | Where-Object -Property defaultBranchRelation -eq "same-as-default").Count }},
    @{ Name="BranchesFastForwardable"; Expression={ @($_.refs | Where-Object -Property defaultBranchRelation -eq "fast-forwardable-to-default").Count }},
    @{ Name="BranchesAheadOfDefault"; Expression={ @($_.refs | Where-Object -Property defaultBranchRelation -eq "ahead-of-default").Count }},
    @{ Name="BranchesNeedsMerge"; Expression={ @($_.refs | Where-Object -Property defaultBranchRelation -eq "needs-merge").Count }},
    @{ Name="BranchesOtherTree"; Expression={ @($_.refs | Where-Object -Property defaultBranchRelation -eq "other-tree").Count }} | Sort-Object -Descending -Property RefsTotal | Format-Table
Write-Output '```'
Write-Output 'Definition:'
Write-Output '* BranchesSameAsDefault - number of branches pointing to same commit as default branch (including default branch).'
Write-Output '* BranchesFastForwardable - number of branches behind of default branch (it can fast forward to default branch) - deleting it will result in no data loss as all commits are referenced also by default branch.'
Write-Output '* BranchesAheadOfDefault - number of branches ahead of default branch (default branch can fast forward to it).'
Write-Output '* BranchesNeedsMerge - number of branches splitted from default branch (needs merge commit or rebase).'
Write-Output '* BranchesOtherTree - number of branches with separate git history - no shared commits with default branch.'

Write-Output ""
Write-Output "## Branches details (non-empty repos)"
$data | Where-Object -Property isEmpty -eq $false | Sort-Object -Property pathName | %{ 
    Write-Output "### Branches details - $($_.pathName)"
    Write-Output ''
    Write-Output "|Branch|Last Commit|Default Branch Relation|"
    Write-Output "|--|--|--|"
    $_.refs | Sort-Object -Property lastCommitDaysAgo | Where-Object -Property isBranch -eq $true | %{
        Write-Output "|``[$($_.name)]``|$($_.lastCommitDaysAgo) days ago|``$($_.defaultBranchRelation)``|"
    }
    Write-Output ''
}
