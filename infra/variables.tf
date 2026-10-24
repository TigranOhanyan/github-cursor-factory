# Inputs. Neither has a default on purpose.
#
# A repository created from this template must target itself, and it
# must use its own passphrase. Defaults would point every copy at one
# repository, or worse, encrypt every copy with a passphrase that is
# sitting in git.

variable "github_repository" {
  type        = string
  description = "Repository whose labels this stack manages, as owner/name. GitHub Actions sets TF_VAR_github_repository from github.repository."
}

variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for state and plan encryption. At least 16 characters. GitHub Actions sets TF_VAR_state_passphrase from the TF_STATE_PASSPHRASE secret. OpenTofu reads TF_VAR_<name> from the environment; it does not read TF_STATE_PASSPHRASE by itself."

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}
