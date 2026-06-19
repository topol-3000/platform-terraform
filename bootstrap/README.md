# bootstrap

Creates the S3 bucket that holds Terraform remote state for the rest of the
repo. This is the one config that **cannot** use the S3 backend (it's what
creates the bucket), so it uses **local state**.

Run it once:

```bash
terraform init
terraform apply
terraform output state_bucket_name
```

Then configure `envs/prod` to use the bucket (see the repo README).

Notes:
- Locking uses S3 native lockfiles (`use_lockfile = true` in the backends), so
  there is **no DynamoDB table** here.
- The bucket has `prevent_destroy = true`. To tear it down you must first remove
  that lifecycle block.
- `bootstrap/terraform.tfstate` is **not** gitignored — commit it so the bucket
  is reproducible. It contains no secrets (just bucket metadata).
