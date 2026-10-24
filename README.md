# github-cursor-factory

This repository is the start of a software factory. The idea is a pipeline where Cursor Automations do judgment work, such as building and reviewing, and GitHub Actions do deterministic work. It is built one step at a time, as code, and this README describes only what is in the repository.

What is here today is OpenTofu that defines six issue labels, and `github/workflows/factory.yml`, which a host copies into its own `.github/workflows/` to plan and apply every `.tf` file in `.factory/`. This factory repository does not run that workflow, and it has no state. How the factory is installed into a host is decided in [ADR: How the factory is distributed and laid out](https://github.com/TigranOhanyan/github-cursor-factory/issues/3).

## Layout

Two workflow directories. `.github/` is Actions for this repository. `github/` (no dot) is workflows a host copies into its own `.github/workflows/`. Actions does not run the files under `github/` here.

```
terraform.tf                              version, provider pin, backend, encryption
variables.tf                              passphrase and the target repository
providers.tf                              GitHub provider
labels.tf                                 the six labels
.terraform.lock.hcl                       provider checksums
github/workflows/factory.yml              copied to the host's .github/workflows/
.github/workflows/validate.yml            fmt, validate, and actionlint on pull requests here
.gitignore                                this repository only; hosts do not copy it
README.md                                 this repository only; hosts do not copy it
```

A host copies files like this:

- Root files that are the stack go to `.factory/`. Today that is `terraform.tf`, `variables.tf`, `providers.tf`, `labels.tf`, and `.terraform.lock.hcl`.
- `github/workflows/*` goes to the host's `.github/workflows/`. The name `factory.yml` keeps it next to workflows the host wrote itself.
- `.github/` is not copied. It is this repository's own CI.
- Root files that belong to this repository as a project are not copied. Today those are `.gitignore` and `README.md`.

In a host repository that looks like:

```
.factory/terraform.tf
.factory/variables.tf
.factory/providers.tf
.factory/labels.tf
.factory/.terraform.lock.hcl
.factory/state/terraform.tfstate          written by apply, committed on the host's default branch
.github/workflows/factory.yml             copied from github/workflows/
```

`state/` is reserved for that file. This repository ships nothing under `state/`. The backend path is `state/terraform.tfstate`, relative to the directory tofu runs in. The workflow runs tofu with `.factory/` as its working directory, so the committed path is `.factory/state/terraform.tfstate`.

Pull requests in this repository run `tofu fmt -check`, `tofu validate`, and [actionlint](https://github.com/rhysd/actionlint) 1.7.12 on `.github/workflows/` and `github/workflows/`. Init uses `-backend=false`, so that job has no backend and writes no state. The passphrase it sets exists only so OpenTofu can load the encryption block.

```mermaid
flowchart TD
  files["OpenTofu files at the factory root"] --> dotfactory["Host copies them into .factory/"]
  wf["github/workflows/factory.yml"] --> hostwf["Host copies it to .github/workflows/"]
  hostwf --> pr["Pull request in the host"]
  hostwf --> push["Push to the host's default branch, or Run workflow"]
  pr --> plan["plan"]
  push --> apply["apply"]
  apply --> state["Commit .factory/state/terraform.tfstate on the default branch"]
```

## Labels

Six labels. An issue should carry one type label. Parent and child relationships are GitHub sub-issues, not labels.

These descriptions are written as facts that stay true. The intended use is to add a label to an issue and leave it there, so an issue can carry `todo` and `in-progress` together and both sentences are still right. The workflow creates the label definitions. It does not attach them to issues.

| Label | Color | Meaning |
| --- | --- | --- |
| `epic` | `#5319E7` | Type. A large outcome, broken into stories. |
| `story` | `#1D76DB` | Type. A user-visible slice of an epic. |
| `task` | `#006B75` | Type. One buildable change. |
| `todo` | `#0E8A16` | Refined: the description is clear and the acceptance criteria are testable given/when/then statements. Any builder, person or agent, can pick it up. |
| `in-progress` | `#FBCA04` | A builder has started. While this label is present, a second builder must not start. |
| `needs-attention` | `#D93F0B` | The pipeline got stuck. A person, or a more capable agent, has to step in. |

`in-progress` is the claim. It is what keeps two builders off the same issue. `needs-attention` is the signal that the usual path cannot continue on its own.

## How a host runs it

`github/workflows/factory.yml` does not run in this repository. A host copies it to `.github/workflows/factory.yml`, and that workflow plans and applies every `.tf` file in `.factory/`. It runs:

- A pull request that changes `.factory/` or that workflow, opened from the host repository: plan. A pull request from a fork is skipped, because it does not receive the passphrase secret.
- A push to the host's default branch that changes those paths, and **Run workflow** from that branch: apply, then commit `.factory/state/terraform.tfstate` and push that commit to the same branch.

The push trigger listens to every branch. A `branches` filter cannot use an expression, so it cannot name "whatever the default branch is". The apply job is the gate. It reads `repository.default_branch` from the event. That field is on a push. The documented payload for **Run workflow** is `inputs`, `ref`, and `workflow`, so when the field is empty the job asks the API and stops if the answer is empty too. It does not assume the branch is named `main`.

The commit adds that path and nothing else. OpenTofu's `.terraform/` directory, plan files, and `terraform.tfstate.backup` stay untracked. The add is forced, so a host `.gitignore` entry of `*.tfstate*` does not drop the state file.

Two things keep that commit from running the workflow again. The path filters ignore `.factory/state/**`, so a commit that only touches the state file does not match. Separately, a push made with `GITHUB_TOKEN` does not start another workflow run.

Plan and apply share one concurrency group per host, `factory-<owner/name>`. An apply is not cancelled to make room for the next run, so two applies never overlap.

Each job sets its own permissions. Plan uses `contents: read` and `issues: read`. Apply uses `contents: write` and `issues: write`.

The workflow sets `TF_VAR_github_repository` from `github.repository` and `TF_VAR_state_passphrase` from the repository secret `TF_STATE_PASSPHRASE`. OpenTofu reads `TF_VAR_<name>`. The token is the host's `GITHUB_TOKEN`. No personal access token.

Apply writes the state file again even when the resources did not change, because encryption uses a new nonce. The workflow commits it when the bytes differ. The file is JSON. Resource names and ids sit inside `encrypted_data`. The diff is not a review of those resources.

Run tofu through the workflow. `.factory/` has no `.gitignore`. If you run tofu by hand, you have to keep `.factory/.terraform/` out of git yourself, and the same for plan files and `terraform.tfstate.backup`. A local apply also rewrites the state file with whatever passphrase is in your shell.

## Manual setup for a host

Copying is by hand. A CLI for this install is not in this repository ([issue #2](https://github.com/TigranOhanyan/github-cursor-factory/issues/2)). Do this before the first plan or apply.

1. From the host repository, copy the stack into `.factory/` and the workflow into `.github/workflows/`. `ref=main` is a revision of this factory repository. A commit SHA pins that revision. It is not the host's default branch.

   ```bash
   mkdir -p .factory .github/workflows
   ref=main
   repo=TigranOhanyan/github-cursor-factory
   base="https://raw.githubusercontent.com/$repo/$ref"
   for f in terraform.tf variables.tf providers.tf labels.tf .terraform.lock.hcl; do
     curl -fsSL -o ".factory/$f" "$base/$f"
   done
   curl -fsSL -o .github/workflows/factory.yml "$base/github/workflows/factory.yml"
   ```

2. Generate a passphrase of at least 16 characters:

   ```bash
   openssl rand -base64 32
   ```

   Copy that single line, with no extra space and no extra newline. Store it in a password manager and in a second backup you can open if the password manager is lost. The passphrase is not in either repository. OpenTofu cannot reconstruct it. Keep the same value for as long as the state file exists. Replacing the secret with a different passphrase makes the existing file unreadable.

   If the passphrase is lost, delete `.factory/state/terraform.tfstate` from the host's default branch and run the workflow again. The labels stay on GitHub. The GitHub provider looks a label up by name and updates it, so a new state file can be written without importing by hand.

3. In the host repository: **Settings → Secrets and variables → Actions → New repository secret**.

   - Name: `TF_STATE_PASSPHRASE`
   - Secret: the line from step 2

4. Commit `.factory/` and `.github/workflows/factory.yml` to a pull request, or straight to the default branch, after the secret exists. The pull request plans. The merge, or **Actions → Factory → Run workflow** on the default branch, applies and creates the state file.

   You do not create the six labels by hand. If apply fails with a 403, the host's default token is read-only and the job permissions could not raise it. Set **Settings → Actions → General → Workflow permissions** to read and write, then re-run the workflow.

## Architecture decisions

**OpenTofu, with state encryption.** The host commits its state file, so the file has to be encrypted. OpenTofu encrypts state and plan files itself, since version 1.7, with a PBKDF2 passphrase and AES-GCM. `enforced = true` refuses a plaintext state or plan. HashiCorp Terraform does not have that feature. OpenTofu is also open source under the MPL. OpenTofu in the workflows is pinned to 1.13.2, and the GitHub provider is pinned to 6.13.0.

**The factory is source, not a project that applies.** The OpenTofu files live at the root of this repository. A host copies them into `.factory/`. Workflows that belong to a host live in `github/workflows/` and are copied into that host's `.github/workflows/`, where they run as the host's own workflows. `.github/` in this repository is only this factory's CI, so a push here does not apply anything. State is the host's, on the host's default branch, at `.factory/state/terraform.tfstate`. The reasoning for this shape, including why this is not a template repository, is [ADR #3](https://github.com/TigranOhanyan/github-cursor-factory/issues/3).

**Encrypted state in git.** The state file is small. It is stored in the host's git repository, encrypted, instead of in a remote backend such as S3 or HCP Terraform. A remote backend would be another account and another set of credentials. The passphrase is an Actions secret on that host.

**Non-authoritative labels.** Each label is a `github_issue_label`, created with `for_each` over a map. Labels that are not in the map, including GitHub's defaults, are left alone. The resources set `prevent_destroy`, so removing a name from the map fails the apply instead of deleting the label on GitHub.

**Add-only labels.** Descriptions record something that remains true after the label is added: the issue is of a certain type, it was refined, a builder started, or the pipeline got stuck. `in-progress` staying in place is what stops a second builder from starting.
