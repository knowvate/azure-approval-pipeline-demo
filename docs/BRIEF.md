# Brief: a safe approval pipeline for one shared Azure subscription

This is a hand-over note for an engineer, or an AI assistant such as
Claude, who is applying this repo's pattern to a real codebase. Read it
before changing anything. It explains what we're after and why each piece
exists, so the pattern can be adapted without losing the safety properties.

Reference implementation: this repo, especially
`.github/workflows/pipeline.yml`, `.github/workflows/deploy-environment.yml`
and `bootstrap/main.tf`. It ran end to end for real (Development deployed
automatically; UAT and Production were approved through the GitHub
dialog), and was then torn down.

## The situation it is designed for

- Development, UAT and Production all live in **one Azure subscription**.
- The only thing that tells environments apart is an `Environment` tag with
  values `Development`, `UAT`, `Production`.
- The pipeline must cover the usual stages: Terraform, lint, unit tests,
  build and a security scan. Then it promotes through the environments, with
  a human approval before UAT and before Production.

**Tags are labels, not permissions.** Anyone or anything with Contributor on
the subscription can change Production, or change the tag. Azure RBAC can't
be scoped to "resources tagged Production", so you can't build a safe gate
on tags. The design below creates real boundaries inside the one
subscription instead.

## The goal in one sentence

Nothing can change Production unless a named human has approved that
specific Terraform plan and build in GitHub, and even a buggy or malicious
workflow on another branch or environment physically can't get credentials
that reach Production.

## Non-negotiable properties

Keep all of these when adapting. If the target setup can't support one,
stop and flag it rather than quietly dropping it.

1. **One resource group per environment.** This gives RBAC a real scope.
   If today's environments share resource groups, splitting them is the
   first piece of work, before any pipeline changes. Keep the tags too;
   they're still useful for cost reports and policy.
2. **Two identities per environment**, with roles on that environment's
   resource group only:
   - **plan**: a read-only custom role (`*/read`, plus any narrowly needed
     list actions; see *Lessons* below). Its OIDC federated credential
     trusts `…:ref:refs/heads/main`, so plans run before approval and can't
     change anything. Pull requests get the subject `…:pull_request`, so they
     can't log in at all.
   - **deploy**: Contributor on that one resource group. Its federated
     credential trusts **only** `…:environment:<env>`. A job can only enter
     the GitHub environment after it passes that environment's protection
     rules. So as far as Azure is concerned, the federated credential *is*
     the approval gate.
3. **The GitHub environments carry the gate**, and settings aren't YAML, so
   a pull request can't remove them:
   - `uat` and `production` have required reviewers;
   - **"Allow administrators to bypass configured protection rules" is
     unticked.** GitHub ticks it by default;
   - the deployment branch policy is `main` only;
   - deploy-identity client IDs are *environment* variables, readable only
     by jobs that passed the gate.
4. **Separate Terraform state per environment**: one container each, writable
   only by that environment's identities, Entra ID auth only, and shared keys
   disabled on the storage account.
5. **Identities and state live outside the environment resource groups**
   (a `shared` group). A deploy identity with Contributor on its group then
   can't delete itself, re-point its own trust, or touch another
   environment's state.
6. **Apply the saved plan.** The reviewer reads the plan in the run summary.
   The deploy job runs `terraform apply tfplan` on that exact file. If state
   changed in between, Terraform refuses the stale plan.
7. **Build once and promote the artifact.** Production runs the same bytes
   that Development and UAT ran. The smoke test checks that the deployed
   version equals `github.sha`.
8. **No stored Azure secrets.** Use OIDC everywhere. Workflows declare
   `permissions: {}` at the top and grant `id-token: write` per job.

## Pipeline shape

```
Lint ──────┐
Unit tests ┴─▶ Build ─┐
Terraform validate ───┼─▶ Development ─▶ UAT ──────────────▶ Production
Security scan ────────┘   plan → deploy   plan → ⏸ → deploy   plan → ⏸ → deploy
```

- Use one workflow, so GitHub draws one graph (similar to an AWS
  CodePipeline view).
- Each environment is a call to a reusable workflow
  (`deploy-environment.yml`) with two jobs: **Plan** (no environment, plan
  identity) and **Deploy** (in the environment, deploy identity).
- Pull requests run checks and the build only; deploys start from `main`.
- Concurrency is one deploy at a time. A newer push queues behind a run that
  is waiting for approval rather than cancelling it.
- Third-party actions are pinned by commit SHA.
- Checkov hard-fails. Deliberate exceptions are inline
  `#checkov:skip=ID:reason` comments next to the resource.

## Things that will differ at work, and need checking first

Questions to answer before writing code:

- **GitHub plan.** Required reviewers on environments in a **private** repo
  need GitHub Team or Enterprise. The demo repo is public because of the
  free plan.
- **Who can create role assignments?** The `bootstrap/` stack needs Owner,
  or User Access Administrator plus Contributor, on the subscription. This is
  often a platform or cloud team. Bootstrap is meant to be applied once by a
  person, not by the pipeline.
- **Existing resources.** Is everything already in per-environment resource
  groups? Is existing Terraform state shared across environments? Moving
  state means `terraform state mv`, or `import` blocks into per-environment
  state.
- **Network.** If state storage or the targets use private endpoints,
  GitHub-hosted runners can't reach them. You would need self-hosted runners
  or a runner VNet integration, and the OIDC subjects stay the same.
- **Azure Policy** in the subscription, such as required tags or allowed
  locations, can deny resources the pipeline creates. Read the assignments
  first.
- **OIDC subject format.** Get the real prefix with
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`.
  Some organisations use the immutable `repo:owner@<id>/repo@<id>` form
  instead of `repo:owner/repo`. If the prefix is wrong, every Azure login
  fails with AADSTS70021.
- **App type.** The demo deploys a zip to App Service. Swap the deploy step
  for whatever the workload is (container push, Function App, AKS). The plan
  and approve flow stays the same.

## Lessons from actually running it

- **Reader is not enough for plans on App Service.** Terraform reads app
  settings via a POST `Microsoft.Web/sites/config/list/action`, so the
  planner role adds that action. Other resource types have similar "list"
  reads, for example storage keys and Key Vault. Add them case by case;
  never add write actions.
- **Set `resource_provider_registrations = "none"`** in the azurerm
  provider. Otherwise azurerm tries to register providers at subscription
  scope, which a resource-group-scoped identity can't do.
- **Use the azurerm backend with `use_azuread_auth = true` and
  `use_oidc = true`.** It needs Storage Blob Data Contributor on the
  container, because plans take a lock too, plus Reader on the account.
- **A plan file can contain secrets.** Keep artifact retention short (the
  demo uses 3 days), and restrict artifact download in private repos.
- The step summary is capped at 1 MiB, so the full plan is truncated to
  about 900 KB inside a `<details>` block.

## Suggested order of work in a real repo

1. Inventory: resource groups, tags, state, policies, and the GitHub plan.
2. Split or confirm per-environment resource groups.
3. Write and apply `bootstrap` (identities, federated credentials, custom
   planner role, role assignments, state containers). A person with Owner
   applies it locally.
4. Migrate state to per-environment containers.
5. Create the GitHub environments, reviewers, branch policy and
   variables, with admin bypass off.
6. Add the pipeline: checks first (on PRs), then Development, then UAT and
   Production gates.
7. Remove any old broad credentials, such as subscription-wide service
   principal secrets.

## Longer term

Separate subscriptions per environment (an Azure landing zone) are the
stronger answer. Every control above carries straight over, and
subscription-level policy and budgets then separate cleanly too.
