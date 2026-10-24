# github.repository looks like "octocat/hello-world": owner, slash, name.
# The provider wants the owner. The label resource wants the name only.

locals {
  github_repository_parts = split("/", var.github_repository)
  github_owner            = local.github_repository_parts[0]
  repository_name         = local.github_repository_parts[1]
}

provider "github" {
  owner = local.github_owner

  # The token is the GITHUB_TOKEN environment variable.
  # In GitHub Actions that is the built-in token for this repository.
  # No personal access token.
}
