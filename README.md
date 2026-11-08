# Azure approval pipeline demo

A GitHub Actions pipeline that lints, tests, builds and scans, then promotes
one build through **Development → UAT → Production** with Terraform, with
human approval before UAT and Production.

All three environments live in **one Azure subscription**, told apart only
by an `Environment` tag (`Development`, `UAT`, `Production`). That's a
common real-world starting point, and on its own it isn't safe: a tag is a
label, not a permission boundary. This repo shows how to make that setup
safe without moving to separate subscriptions.

## The pipeline

```
Lint ──────┐
Unit tests ┴─▶ Build ─┐
Terraform validate ───┼─▶ Development ─▶ UAT ──────────────▶ Production
Security scan ────────┘   plan → deploy   plan → ⏸ → deploy   plan → ⏸ → deploy
```

- **Pull requests** run lint, tests, Terraform validate, Checkov and the
  build. Nothing deploys from a PR.
- **On `main`**, each environment runs two jobs from
  `deploy-environment.yml`:
  - **Plan** runs immediately under that environment's **read-only**
    identity and writes the plan to the run summary.
  - **Deploy** runs in the GitHub environment. For UAT and Production it
    waits for a required reviewer, who reads the plan first. It then
    applies **exactly that saved plan** and deploys the **same build
    artifact** Development got, then smoke-tests it.

## What makes one subscription safe

| Control | Where | What it stops |
|---|---|---|
| One resource group per environment | `bootstrap/` | Gives each environment a real scope for RBAC |
| Separate identity per environment, Contributor on its own resource group only | `bootstrap/` | The Development pipeline can't touch Production, even by mistake |
| Read-only plan identity (custom role: `*/read` only) | `bootstrap/` | A plan can never change anything, so it can run before approval |
| Deploy identity trusts only its GitHub environment (OIDC subject `…:environment:production`) | `bootstrap/` | No job can get Production credentials without passing the approval gate |
| Required reviewers + "main only" branch policy, admin bypass off | GitHub environment settings | Nothing reaches UAT/Production unapproved, or from an unmerged branch, and admins can't skip the gate (GitHub allows admin bypass by default). Settings aren't YAML, so a PR can't remove them |
| Separate Terraform state per environment, writable only by that environment's identities | `bootstrap/` | A Development run can't corrupt Production's state |
| Saved plan applied | `deploy-environment.yml` | What's applied is what was approved; a stale plan is refused |
| Build once, promote the artifact | `pipeline.yml` | Production runs the bytes that were tested in Development and UAT |
| No stored credentials (OIDC) | everywhere | Nothing to leak or rotate |

Identities and state sit in a separate `rg-approvaldemo-shared` group, so a
deploy identity can't delete itself or another environment's state.

Separate subscriptions per environment (an Azure landing zone) remain the
stronger long-term answer. With them, subscription-level policies and
budgets also separate cleanly. Everything above carries straight over.

## Layout

```
app/          Node web app (ESLint, node:test, build → dist/)
infra/        What the pipeline deploys: App Service F1 plan + web app per environment
  envs/       development.tfvars, uat.tfvars, production.tfvars
bootstrap/    One-time, applied locally by an Owner: resource groups, identities,
              federated credentials, custom role, role assignments, state storage
.github/workflows/
  pipeline.yml            The whole pipeline
  deploy-environment.yml  Plan + gated deploy for one environment (called 3 times)
```

## Setting it up

1. `cd bootstrap`, create `terraform.tfvars` with `subscription_id` and
   `github_oidc_subject_prefix` (from
   `gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`),
   then `terraform init && terraform apply` as a subscription Owner.
2. Repo variables: `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
   `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, and
   `PLAN_CLIENT_ID_DEV|UAT|PROD` from the bootstrap outputs.
3. GitHub environments `development`, `uat`, `production`, each with a
   deployment branch policy of `main`. Add required reviewers to `uat` and
   `production`, and untick "Allow administrators to bypass configured
   protection rules" on both. Each environment gets variables `AZURE_CLIENT_ID` (its
   deploy identity) and `RESOURCE_GROUP`.

## Tearing it down

Destroy each environment's infra (`terraform destroy` in `infra/` with that
environment's backend config and tfvars), then `terraform destroy` in
`bootstrap/`. Cost while it runs is about £0: F1 App Service is free, and
state storage is pennies a month.
