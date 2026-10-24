# OpenTofu settings for this stack.
#
# Run every tofu command from infra/. The GitHub Actions workflow does.
# State encryption needs OpenTofu 1.7 or newer. CI installs 1.13.2.
# required_version stops an older CLI, which would not understand
# the encryption block.

terraform {
  required_version = ">= 1.13.2"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }

  # Local backend: one file on disk, no remote backend account.
  # The path is relative to infra/. CI checks the tofu-state branch
  # out at ../tofu-state before plan and apply. The file is created
  # on the first apply. It is gitignored on main and committed only
  # on that branch.
  backend "local" {
    path = "../tofu-state/labels.tfstate"
  }

  # Encrypt state and plan files before they touch disk.
  # The passphrase is var.state_passphrase (TF_VAR_state_passphrase).
  # The file stores a salt, not the passphrase.
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.state_passphrase

      # Recorded inside the encrypted file. Leave it alone, or
      # existing state will not decrypt even if the passphrase is right.
      encrypted_metadata_alias = "passphrase"
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    # enforced refuses a plaintext file. There is no unencrypted
    # fallback: this stack has never written plaintext state.
    # The same rules apply to plan files.
    state {
      method   = method.aes_gcm.default
      enforced = true
    }

    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}
