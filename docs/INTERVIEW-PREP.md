# Interview Prep: Presenting This Project

## Be honest about what it is

Present this as **a project you built to practise the industry pattern**, not as something from a previous employer. Interviewers respect "I built this to learn how it's done properly, and here's what I'd change at company scale" far more than a claim that falls apart under follow-up questions. Everything below is written that way.

---

## The 2-minute walkthrough

Open the README architecture diagram while you talk.

> "I built a multi-environment Terraform platform on AWS to practise how infra is managed end to end.
>
> **Structure.** There are three layers. A `bootstrap` layer runs once and creates a separate S3 state bucket per environment, the GitHub OIDC provider, and IAM roles. Then reusable `modules`: network, DynamoDB, a Lambda app and monitoring. Then `envs/dev` and `envs/prod`, which call the **same modules**. Their `main.tf` files are identical; I can diff them live. The only differences are `terraform.tfvars` for sizing and protection, and `backend.tf` pointing at a different state bucket.
>
> **State.** Each environment has its own versioned, encrypted S3 bucket with public access blocked and HTTPS enforced. Locking uses Terraform's S3-native lock file, so no DynamoDB lock table. The dev pipeline role has an explicit IAM deny on the prod bucket, so dev can never read or corrupt prod state.
>
> **Pipeline.** On a pull request, GitHub Actions runs fmt, tflint and checkov, then plans **both** environments with **read-only** roles and posts the plans as PR comments. After merge, dev applies automatically with a smoke test. Prod is planned, the plan file is saved, and the job pauses on a GitHub Environment with a required reviewer. After approval it applies **that exact plan file**. The prod apply role's trust policy only accepts tokens from the `prod` environment, so the approval can't be bypassed.
>
> **Security.** No AWS keys anywhere: OIDC with one-hour credentials. The apply role can only manage IAM roles prefixed with its own environment, and its own role name is outside that prefix, so it can't escalate itself. The app runs in private subnets with no NAT or internet gateway and reaches DynamoDB through a gateway endpoint. Prod has deletion protection and point-in-time recovery, and a variable validation makes it impossible to switch deletion protection off in prod.
>
> **Day 2.** A scheduled drift-detection job runs `plan -detailed-exitcode` every day and opens a GitHub issue if someone changed something in the console.
>
> **Cost.** I designed it to run entirely on Always Free services, so it costs zero. In a company I'd add separate AWS accounts, customer-managed KMS keys, and versioned modules."

---

## Live demo order (if they let you share your screen)

1. `diff envs/dev/main.tf envs/prod/main.tf` (no output), then `diff envs/dev/terraform.tfvars envs/prod/terraform.tfvars`.
2. Open both app URLs side by side.
3. Show a merged PR with the two plan comments (dev: 1 change, prod: no changes).
4. Show an Actions run with the prod approval step.
5. Show the drift issue.
6. Open `bootstrap/main.tf` at the `DenyOtherEnvironmentState` statement.

---

## Why I made each decision

| Decision | Why | Trade-off I'd mention |
|---|---|---|
| Separate directories per env, not workspaces | Each env gets its own backend config, its own IAM role and its own bucket. With workspaces, all envs share one backend and the same credentials, and it's easy to run in the wrong workspace. | Some duplicated boilerplate (backend, providers). Terragrunt can remove it at scale. |
| One state bucket per env | Blast radius and access control. I can deny dev access to prod state at the IAM level. | One more bucket to manage. |
| S3-native locking (`use_lockfile`) | Supported since Terraform 1.10; one less resource. The DynamoDB lock table approach is now deprecated in the S3 backend. | Needs Terraform 1.10+. |
| OIDC instead of access keys | No secret to leak or rotate; credentials last 1 hour and are scoped to repo + branch/environment. | Initial setup is slightly more complex. |
| Separate plan and apply roles | PRs can come from any branch, so they only get read access. Only merged code reaches the apply role. | Two roles per env. |
| Save the prod plan and apply that file | The approver approves exactly what will be applied. If state changed in between, Terraform refuses the stale plan. | Plan artifact must be stored briefly (3-day retention). |
| Prod approval via GitHub Environments | Approval is enforced by AWS (trust policy), not just by YAML. | Required reviewers need a public repo or a paid GitHub plan. |
| Variable validation for prod deletion protection | A guardrail in code: even a reviewed PR can't disable it. | To destroy prod you must disable protection out of band, which is intentional. |
| Lambda + DynamoDB, no NAT | Always Free, and private networking via a free gateway endpoint. | No outbound internet from the function; would need NAT or interface endpoints for other AWS services. |
| Provisioned DynamoDB capacity | Covered by Always Free and caps cost: extra traffic is throttled, not billed. | Can throttle under real load; on-demand or autoscaling in a real system. |
| Every Checkov skip is inline with a reason | Exceptions are reviewable in the PR, next to the code they affect. | Needs discipline to keep the reasons honest. |

---

## Follow-up questions and answers

**Q: How do you make sure dev and prod don't drift apart in code?**
Both environments call the same modules and their `main.tf` files are identical. Differences are only allowed in tfvars. In a bigger setup I'd version modules with Git tags and have prod pin a tag that has already been running in dev.

**Q: How would you roll out a module change to dev first, but not prod?**
Today, a module change goes to dev on merge, and prod only after a reviewed plan and approval. For stricter control, I'd publish modules with semantic version tags and reference them as `source = "git::https://github.com/org/modules.git//network?ref=v1.3.0"`; dev moves to `v1.4.0` first and prod is bumped in a separate PR.

**Q: Two engineers run apply at the same time. What happens?**
The second one fails to acquire the lock, because the first created the `.tflock` object with a conditional write. In this repo it's also prevented in CI by the `concurrency` group on the deploy workflow.

**Q: The pipeline says "Error acquiring the state lock" but nobody is running anything.**
Usually a cancelled job left the lock. I'd confirm no run is active in Actions, check the lock info (who and when) in the error, and then run `terraform force-unlock <LOCK_ID>`. Never force-unlock while a run is active.

**Q: Someone deleted or corrupted the state file. How do you recover?**
The bucket is versioned, so I'd restore the previous version of the object from the S3 console or CLI. For a single missing resource I could use `terraform import`.

**Q: Where are your secrets?**
There aren't any. GitHub authenticates with OIDC, and the Lambda accesses DynamoDB with its IAM role. If the app needed a secret, I'd store it in SSM Parameter Store or Secrets Manager and grant the function read access to only that parameter, never put it in tfvars or state.

**Q: Isn't PowerUserAccess too broad for the apply role?**
It's a pragmatic baseline, narrowed by an inline policy: IAM is limited to roles with this environment's prefix, other environments' state buckets are explicitly denied, and resources tagged with another environment are denied. At company scale I'd use separate AWS accounts, so the dev role physically can't touch prod, plus SCPs and a tighter custom policy.

**Q: How do you detect manual changes in the console?**
A scheduled workflow runs `terraform plan -detailed-exitcode` daily with the read-only role. Exit code 2 means drift; it opens a GitHub Issue with the diff. The fix is to revert the manual change or codify it via a PR.

**Q: How do you stop a PR from a fork from deploying or reading your AWS account?**
GitHub doesn't issue OIDC tokens to workflows triggered from forks, and the plan role only trusts this repository. The apply role only trusts the `dev` and `prod` GitHub Environments, which only run from `main`.

**Q: What does `terraform plan -out` give you over just running apply?**
It guarantees that what's applied is exactly what was reviewed. Without it, something could change between review and apply.

**Q: Why commit `.terraform.lock.hcl`?**
It pins exact provider versions and checksums, so every laptop and every CI run uses the same provider build. I generate it for Linux, Windows and macOS so CI and all developers work.

**Q: How would you do this across multiple AWS accounts?**
AWS Organizations with a dev account and a prod account. Each account has its own state bucket and its own OIDC roles, and the provider uses the role for that account. The repo structure stays the same; only `backend.tf` and the role ARNs change.

**Q: How would you handle a `terraform destroy` on prod?**
It's deliberately hard. Deletion protection is on and enforced by validation, so you'd have to disable it outside the normal flow, which leaves an audit trail in CloudTrail. In a team I'd also require a separate approval for destroy runs.

**Q: What would you improve next?**
Separate accounts, customer-managed KMS keys, module versioning, pinning GitHub Actions to commit SHAs with Dependabot, Infracost and OPA policy checks on PRs, and CloudFront + WAF in front of the app.

**Q: What was the hardest part?**
(Answer from your own experience. Good honest examples: getting the OIDC trust policy `sub` claims right for pull requests vs environments, the lock file checksum error in CI, or understanding why saved plans need the Lambda zip uploaded alongside them.)

---

## Resume bullet points

- Designed a multi-environment (dev/prod) AWS platform with Terraform using shared modules and isolated S3 remote state per environment, with S3-native state locking.
- Built a GitHub Actions CI/CD pipeline with OIDC (no static credentials), read-only plan roles for pull requests, automated dev deployments, and approval-gated prod applies of the reviewed plan file.
- Shifted security left with tflint and Checkov on every PR (0 open findings, all exceptions documented), and added daily drift detection that raises GitHub issues automatically.
- Implemented least-privilege IAM guardrails: environment-scoped role permissions, explicit deny on cross-environment state, and prevention of pipeline privilege escalation.
- Architected the workload on serverless Always Free services (Lambda, DynamoDB, private VPC with gateway endpoint), running at $0/month.
