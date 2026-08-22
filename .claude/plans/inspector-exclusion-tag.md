# Task: launch-time `InspectorEc2Exclusion` tag + `ec2:DeleteTags`

**Status:** implemented on 2026-08-22, not yet integration-tested. The Puppet half was already merged.
Plan reviewed against the repo and against jumphost commit `e011bde` first — the IAM scoping, the
infrahouse-core bump and the checklist below changed as a result.

## Why

AWS Inspector scans a freshly launched instance before `unattended-upgrades` has run, opens a finding for
whatever was pending, and closes it on the next upgrade — but by then it has already **reopened the
vulnerability group**, and a group old enough to be reopened that way breaks the remediation SLA.

The fix is not "patch more often on a timer", it is "don't present an unpatched host to Inspector at all":

```
launch  -> instance tagged InspectorEc2Exclusion   (THIS REPO — not done)
boot    -> apt-get update && unattended-upgrade    (puppet-code, done)
success -> aws ec2 delete-tags Key=InspectorEc2Exclusion  (puppet-code, done)
        -> Inspector's first scan sees a patched host
```

## What is already done (infrahouse/puppet-code)

- `profile::boot_security_upgrade` — patches at boot with a bounded retry budget, then drops the tag.
  PRs #294 (development), #295 (promoted to sandbox + global `modules/`).
- `role::openvpn_server` includes it. **PR #297.**

Tag removal is deliberately **best effort** and never fails a Puppet run: missing permission, missing
`ec2metadata`, or unreadable instance id each log a line and return 0. That is why PR #297 could ship
before this repo caught up — right now openvpn instances simply patch early, which is worth having on
its own.

Prior art: `terraform-aws-jumphost` did exactly this in `e011bde` (see its
`.claude/plans/inspector-exclusion-tag.md`). This module owns its ASG directly in `asg.tf`, same as
jumphost, so the recipe transfers almost verbatim — unlike `terraform-aws-bookstack`, which delegates to
`website-pod` and has no clean per-ASG tag seam.

## ⚠️ The constraint that shapes everything here

**The tag is fail-open.** If an instance launches tagged and nothing removes the tag, that VPN server is
**permanently invisible to Inspector** — strictly worse than today, and silently so.

Both changes below ship **together, in one PR**. Adding the tag without `ec2:DeleteTags` creates the hole.
There is no useful intermediate state.

No opt-in variable: `role::openvpn_server` includes `profile::boot_security_upgrade` in every environment
(`role/` is global-only in puppet-code) and this module does not pin puppet-code — it applies whatever is
in `/opt/puppet-code` — so the removal side is universally present. Tag unconditionally.

## Change 1 — tag instances at launch (`asg.tf`)

Add a static `tag` block to `aws_autoscaling_group.openvpn`, alongside the existing `Name` block (~line 151):

```hcl
  # Keeps Inspector from scanning the instance until profile::boot_security_upgrade
  # has applied pending security updates and removed this tag. See
  # .claude/plans/inspector-exclusion-tag.md -- REQUIRES the ec2:DeleteTags
  # statement in iam.tf, or the instance is excluded forever.
  tag {
    key                 = "InspectorEc2Exclusion"
    propagate_at_launch = true
    value               = "true"
  }
```

Inspector keys off the tag **key**; the value is ignored. jumphost ASGs use `true`, actions-runner ASGs use
`bootstrapping` — both work.

Put it on the **ASG**, not in the launch template's `tag_specifications`. Only the ASG path produces the
`propagate_at_launch` behaviour the removal cycle depends on.

## Change 2 — grant `ec2:DeleteTags` (`iam.tf`)

Add to `data.aws_iam_policy_document.instance_permissions`:

```hcl
  # profile::boot_security_upgrade removes this tag once security updates are
  # applied, so Inspector's first scan sees a patched host. Scoped three ways:
  # only this tag key, only instances, and only instances in this ASG.
  statement {
    actions = [
      "ec2:DeleteTags",
    ]
    resources = [
      "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["InspectorEc2Exclusion"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/aws:autoscaling:groupName"
      values   = [local.asg_name]
    }
  }
```

Two scoping decisions worth not re-litigating later:

- **`resources` is the instance ARN, not `"*"`.** `ec2:DeleteTags` covers nearly every taggable EC2
  resource type, so `"*"` plus a tag condition would also grant tag deletion on volumes, ENIs and
  snapshots that happen to carry the same `aws:autoscaling:groupName` value. `data.aws_caller_identity.current`
  is already used in `iam.tf` (the `autoscaling:SetInstanceHealth` statement).
- **`local.asg_name`, not `aws_autoscaling_group.openvpn.name`.** The resource reference would make the
  policy document depend on the ASG, so on a fresh apply the grant lands *after* the ASG exists and has
  begun launching tagged instances — precisely the fail-open window this whole plan exists to close.
  `local.asg_name` (`asg.tf` ~line 105) is known before either resource, and the `SetInstanceHealth`
  statement already uses it. The neighbouring `ec2:ModifyInstanceAttribute` statement uses the resource
  reference; do not copy that half.

Versus jumphost: same resource scope, but a tighter tag condition — jumphost conditions on
`ec2:ResourceTag/created_by_module`, which covers every instance the module ever created in the account.
Worth backporting the ASG-name condition there.

## Scope: the portal ASG is **not** covered

`portal.tf` instantiates `infrahouse/ecs/aws` with `asg_instance_type` — a second EC2 ASG inside this
module, with the same unpatched-at-first-scan problem. It must **not** be tagged here: its Puppet role does
not include `profile::boot_security_upgrade`, so nothing would ever remove the tag and those instances
would go permanently dark to Inspector. Fixing them belongs in `terraform-aws-ecs`. "openvpn is done" is
not "this module's EC2 footprint is done".

## Gotchas

- **`instance_refresh { triggers = ["tag"] }`** (asg.tf ~line 149) — adding an ASG tag **triggers a rolling
  instance refresh**. Not a no-op apply. `min_healthy_percentage = 100` and
  `max_healthy_percentage = var.asg_instance_refresh_max_healthy_percentage` (default 110), so capacity
  holds and one extra instance launches, but the VPN will cycle its instances. Schedule accordingly.
- **`propagate_at_launch` tags only at launch.** The ASG does not re-apply tags to running instances, so it
  will not fight Puppet's deletion, and deleting a per-instance tag does **not** show as Terraform drift on
  the ASG resource. Tag/untag repeats per launch, which is correct.
- **`max_instance_lifetime = 90 days`** bounds how long a stale, never-reconciled instance can persist.
- **Checkov/Trivy:** no new suppression expected. `.checkov.yml` does not skip CKV_AWS_355/356 and the
  existing wildcard-resource statements already pass; scoping to the instance ARN makes it moot anyway.

## Difference from jumphost worth knowing

jumphost's launch template sets `metadata_options { instance_metadata_tags = "enabled" }`, so a script there
can read the tag from IMDS for free. **This module does not set it** (asg.tf ~line 67).

**Do not copy that setting here.** Nothing in puppet-code reads instance tags, from IMDS or otherwise, so
enabling it would expose every instance tag to any local process with no IAM, in exchange for a feature with
no reader. The integration test is what proves the tag lifecycle works; nothing on the instance needs to.

## Expected behaviour after rollout

Per `loopproof/docs/inspector-exclusion-reconciliation-lag.md`:

- Scans resume immediately after the tag is removed, but **findings take ~1.5–2h of running time** to appear.
- During that lag an unassessed instance reports `ACTIVE / SUCCESSFUL / lastScannedAt=minutes ago /
  0 findings` — indistinguishable from genuinely clean. A null-`lastScannedAt` alert will not catch it.
- One prod jumphost never reconciled at all (13h16m, 0 findings, no structural explanation found).

openvpn runs **two instances**, which matters: the cohort-relative detector proposed in that doc needs a
same-AMI sibling with findings > 0 to compare against. A singleton service would be blind to that failure
mode — one of the reasons BookStack was postponed.

## Checklist

- [x] `asg.tf` — ASG `tag` block
- [x] `iam.tf` — `ec2:DeleteTags` statement
- [x] `requirements.txt` — `infrahouse-core ~= 1.1` → `~= 1.3.0` for `EC2Instance.wait_for_bootstrap()`.
      `~= 1.1` permits but does not force 1.3.x (the installed version here was 1.1.1), so CI could
      otherwise resolve to a version without it.
- [x] `tests/test_module.py` — delete the local `wait_for_puppet()` (~lines 22-56, single call site ~line
      381) and call `instance.wait_for_bootstrap()` instead. That helper was extracted into infrahouse-core
      precisely to kill these per-repo copies, and this is the worst of them: it polls the full 600s even
      after cloud-init has failed, and raises a bare `AssertionError` with no cloud-init diagnostics — an
      expensive failure mode on a 10-minute integration test. Same swap jumphost made in `e011bde`.
- [x] `tests/test_module.py` — wait until the instance is provisioned
      (`instance.wait_for_bootstrap()`), then read the instance tags and assert `InspectorEc2Exclusion`
      is not among them. EC2 tag reads are eventually consistent and `EC2Instance` caches for 10s, so poll
      on a longer interval than that TTL rather than asserting once. On failure, dump the cloud-init log:
      a tag still present means the `ec2:DeleteTags` statement is wrong, and that instance would be
      invisible to Inspector forever. Do not also assert the ASG's launch tags — that reads back what
      Terraform just applied, which is the config asserting itself, not behaviour.
- [x] `docs/security.md` — say that instances are patched before their first Inspector scan, and that the
      exclusion tag is removed by Puppet
- [x] `docs/troubleshooting.md` — entry for "instance still carries `InspectorEc2Exclusion` / invisible to
      Inspector", pointing at the `ec2:DeleteTags` statement and the cloud-init log
- [x] `make format` / `make lint`
- [x] No `terraform-docs` regen: the change adds no variables, and this README has no hand-written IAM
      section (jumphost's did). Leave `README.md` alone.
- [ ] `make test-clean` — not run yet, needs AWS. `pip install -r requirements.txt` first: the local
      infrahouse-core is still 1.1.1, which has no `wait_for_bootstrap()`.

**After merge, on `main`** (not part of the PR): `make release-minor` — it does the CHANGELOG and the
`bumpversion` commit, which updates `README.md`, `locals.tf` and four `docs/*.md`. jumphost did the same:
feature commit `e011bde`, then separate release commits.

## Verification once applied

The integration test is the proof — see the checklist. On a live deployment, the Puppet log on a fresh
instance shows one of:

- `removed InspectorEc2Exclusion from i-...` — the API call succeeded
- `could not remove ... (no ec2:DeleteTags?)` — the IAM statement is wrong or missing

The first message is not by itself proof: `delete-tags` succeeds on a tag that was never there, so it is
logged whether or not this module ever tagged the instance. Confirm out of band:

```bash
aws ec2 describe-tags --filters Name=resource-id,Values=i-... --region us-west-1
```
