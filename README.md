## Troubleshooting OIDC Authentication

During development, the GitHub Actions workflow failed with:

```text
Could not assume role with OIDC:
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

To isolate the cause, the authentication path was checked step by step.

### 1. Verify the IAM Role ARN

First, verify the actual IAM Role ARN:

```powershell
aws iam get-role `
  --role-name github-actions-terraform-role `
  --query "Role.Arn" `
  --output text
```

The ARN configured in GitHub Actions must match this value.

To rule out a GitHub repository variable issue, the Role ARN can also be temporarily specified directly in the workflow:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: arn:aws:iam::<AWS_ACCOUNT_ID>:role/github-actions-terraform-role
    aws-region: ap-northeast-1
```

If the same error occurs with the ARN specified directly, the repository variable is not the cause.

### 2. Verify the IAM Role Trust Policy

Check the trust policy currently applied to the IAM Role:

```powershell
aws iam get-role `
  --role-name github-actions-terraform-role `
  --query "Role.AssumeRolePolicyDocument" `
  --output json
```

Confirm that:

- `Principal.Federated` points to the GitHub OIDC provider
- `Action` is `sts:AssumeRoleWithWebIdentity`
- `aud` matches `sts.amazonaws.com`
- `sub` matches the identity issued by GitHub

### 3. Verify the GitHub OIDC Provider

List the configured OIDC providers:

```powershell
aws iam list-open-id-connect-providers `
  --output table
```

Then inspect the GitHub provider:

```powershell
aws iam get-open-id-connect-provider `
  --open-id-connect-provider-arn "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
```

The expected configuration includes:

```text
Url:
token.actions.githubusercontent.com

ClientIDList:
sts.amazonaws.com
```

### 4. Inspect the Actual GitHub OIDC JWT Claims

If the IAM configuration appears correct but role assumption is still denied, inspect the actual OIDC claims issued by GitHub.

Add the following temporary step **before** `Configure AWS credentials`:

```yaml
- name: Check OIDC claims
  shell: bash
  run: |
    RESPONSE=$(curl -sS \
      -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com")

    TOKEN=$(echo "$RESPONSE" | jq -r '.value')

    python3 - "$TOKEN" <<'PY'
    import sys
    import json
    import base64

    token = sys.argv[1]
    payload = token.split('.')[1]
    payload += '=' * (-len(payload) % 4)

    claims = json.loads(base64.urlsafe_b64decode(payload))

    print("aud:", claims.get("aud"))
    print("sub:", claims.get("sub"))
    print("repository:", claims.get("repository"))
    print("ref:", claims.get("ref"))
    PY
```

Example output:

```text
aud: sts.amazonaws.com
sub: repo:<owner>@<owner-id>/<repository>@<repository-id>:ref:refs/heads/main
repository: <owner>/<repository>
ref: refs/heads/main
```

The complete JWT changes between token requests, but identity claims such as the repository owner ID and repository ID are used to identify the repository.

### 5. Compare the JWT Claims with the Trust Policy

The actual `aud` and `sub` values must satisfy the IAM Role trust policy.

Example:

```hcl
Condition = {
  StringEquals = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }

  StringLike = {
    "token.actions.githubusercontent.com:sub" = "repo:<owner>@<owner-id>/<repository>@<repository-id>:*"
  }
}
```

In this project, inspecting the JWT revealed that the actual GitHub OIDC `sub` did not match the value originally configured in the IAM trust policy.

The troubleshooting process therefore isolated the issue as:

```text
GitHub Actions workflow      OK
        ↓
OIDC token request           OK
        ↓
JWT aud                      OK
        ↓
JWT sub                      MISMATCH
        ↓
IAM Trust Policy             DENIED
        ↓
sts:AssumeRoleWithWebIdentity failed
```

After updating the IAM trust policy to match the actual GitHub OIDC subject, the workflow was able to assume the IAM Role successfully.

> The `Check OIDC claims` step is intended for troubleshooting and can be removed after the trust relationship has been verified.