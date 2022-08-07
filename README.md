# Project Analysis Script

This is ad-hoc analysis tool for Azure DevOps repos.

Tool collects data via Azure DevOps REST API and generates markdown file report.

Features:
* Tree list of projects / repos
* List of empty repos
* List of large repos
* List of inactive repos
* List of branches for each repo with relation to default branch and last commit date
* List of number of refs (branches and tags) per repo with statistics of branches statuses (fast-forwardable to default branch, etc.)

## Steps

### 0. Have AzureDevOps Token

On Azure DevOps website click `User Settings > Personal Access Tokens`. Generate token with read access to _Code_. 

Store credetinals to 1Password as API credentials. Add custom `baseurl` field with base organization DevOps URL (example: `https://dev.azure.com/my-organization`). For specific item name and location see [`.env` file](./fetch-project-data.env).
 
### 1. Collect Data From AzureDevOps Server

Fetch data witch script [`fetch-project-data-run.ps1`](./fetch-project-data-run.ps1). This script requires 1Password CLI installed and credentials stored in vault. 

To run it without 1Password, use directly [`fetch-project-data.ps1`](./fetch-project-data.ps1). Script will ask for specific env variables to be set.

### 2. Analyze Data and Generate Report

Run script: [`analyze-projects-run.ps1`](./analyze-projects-run.ps1)