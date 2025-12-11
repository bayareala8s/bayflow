
# BayFlow v1 – Mini Product (Backend Only)

This repo contains a **production-ready AWS backend** for BayFlow v1:

- AWS Transfer Family (SFTP) → S3 landing bucket
- EventBridge → Step Functions → Lambda mover
- Config-driven routing via `config/partners.json.tmpl`
- Job tracking in DynamoDB
- Alerts in SNS + CloudWatch alarms

## Structure

- `infra/main.tf` – single-file Terraform for the full stack
- `lambda/mover/app.py` – Lambda that moves files, archives, and tracks jobs
- `config/partners.json.tmpl` – template for partner/flow configuration

## Prerequisites

- Terraform >= 1.5
- AWS credentials configured (e.g., via profile or environment)
- An SSH key pair for the demo SFTP user `acme`

## Deploy (dev)

```bash
cd infra

terraform init

terraform apply \
  -var "project_name=bayflow" \
  -var "aws_region=us-west-2" \
  -var "alerts_email=himanshu.bhadra@bayareala8s.com" \
  -var "acme_ssh_public_key=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfrEwSO0693t8MHJEi25aNcCgsGGcVumsqzqtvFuH1m bayflow-acme"
```

## Using BayFlow v1

1. After `terraform apply`, note the outputs:
   - `transfer_server_id`
   - `landing_bucket`
   - `target_bucket`
   - `config_bucket`

2. In the AWS console, find the **Transfer Family endpoint** for the server ID.

3. Connect via SFTP client:

   - Host: Transfer Family endpoint hostname
   - Port: 22
   - Username: `acme`
   - Auth: SSH key matching `acme_ssh_public_key`

4. Upload a test file to:

   ```text
   partners/acme/inbox/test.csv
   ```

5. End-to-end flow:

   - S3 ObjectCreated event -> EventBridge -> Step Functions state machine
   - State machine invokes Lambda mover
   - Lambda reads `config/partners.json` from the config bucket
   - File is copied to target bucket under prefix `acme/inbox/processed/`
   - Optional archive copy into `acme/archive/` prefix in the landing bucket
   - Job record created/updated in DynamoDB table `${project_name}-jobs`
   - SNS email is sent on success or failure

You can now iterate on:

- `config/partners.json.tmpl` for new partners/flows
- `lambda/mover/app.py` for additional logic (checksum, tagging, etc.)
- Splitting `infra/main.tf` into modules (`core`, `transfer`, `orchestration`) as needed.
