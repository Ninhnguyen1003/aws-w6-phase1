# W6 Evidence Template

> Personal AWS W6 project – `ap-southeast-1`  
> Fill in screenshots, CLI output, and console links after deployment.

## 1. Student / Project Info

| Field | Value |
|-------|-------|
| Name | Nguyen Quach Khang Ninh |
| Student ID | XB-DN26-014 |
| Region | ap-southeast-1 |
| Project prefix | w6-personal |
| Key pair | ninh_dev |
| Deploy date | 2026-06-25 |

## 2. Deployment Evidence

### 2.1 Terraform apply

```bash
cd aws-w6
terraform init
terraform plan
terraform apply
```

Paste `terraform apply` summary:

```
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.
```

> **Lưu ý:** Account chưa có VPC → đã chạy `aws ec2 create-default-vpc --region ap-southeast-1` trước khi apply.

### 2.2 Key outputs

| Output | Value |
|--------|-------|
| EC2 instance ID | i-0ce721101becfddf4 |
| Public IP | 54.151.147.214 *(đổi sau khi stop/start)* |
| Flask URL | http://54.151.147.214 |
| Security group ID | sg-0054be3091feeb65c |
| Dashboard URL | https://ap-southeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-1#dashboards:name=w6-personal-dashboard |

## 3. EC2 + Flask App

### 3.1 Instance running

- [ ] Screenshot: EC2 console – instance `w6-personal-flask` running
- [ ] Tag `Environment=dev` visible

### 3.2 Flask app accessible

```bash
curl http://54.151.147.214/
curl http://54.151.147.214/health
```

Response:

```
<h1>W6 Flask App</h1><p>AWS Week 6 – ap-southeast-1</p>
{"service":"w6-flask","status":"ok"}
```

- [ ] Screenshot: browser showing Flask homepage

## 4. Security Guard Lambda

### 4.1 Open SSH rule (before)

Manually add open SSH for demo:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0054be3091feeb65c \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --region ap-southeast-1
```

- [ ] Screenshot: SG inbound rule `SSH 0.0.0.0/0`

> **Đã test 2026-06-25:** Rule SSH mở đã bị revoke bởi Security Guard. Ngày báo cáo cần **thêm lại rule SSH** trước khi chụp screenshot "before".

### 4.2 Lambda invocation

```bash
aws lambda invoke \
  --function-name w6-personal-security-guard \
  --region ap-southeast-1 \
  out.json && type out.json
```

Response:

```json
{"revoked_count": 1, "revoked_rules": [{"GroupId": "sg-0054be3091feeb65c", "GroupName": "w6-personal-flask-sg", "RuleId": "sgr-05f5407bf28fc4359"}]}
```

### 4.3 Rule revoked (after)

- [ ] Screenshot: SG – open SSH rule removed
- [ ] CloudWatch custom metric `W6/Security` / `SSHRulesRevoked` > 0

## 5. Cost Guard Lambda

### 5.1 Instance running with tag

- [ ] Screenshot: EC2 `Environment=dev`, state `running`

### 5.2 Lambda invocation

```bash
aws lambda invoke \
  --function-name w6-personal-cost-guard \
  --region ap-southeast-1 \
  out.json && type out.json
```

Response:

```json
{"environment_tag": "dev", "stopped_count": 1, "stopped_instance_ids": ["i-0ce721101becfddf4"]}
```

### 5.3 Instance stopped

- [ ] Screenshot: EC2 state `stopped`
- [ ] CloudWatch custom metric `W6/Cost` / `InstancesStopped` > 0

> Restart manually for further testing:  
> `aws ec2 start-instances --instance-ids i-0ce721101becfddf4 --region ap-southeast-1`

## 6. EventBridge Schedules

| Rule | Schedule | Target |
|------|----------|--------|
| w6-personal-security-guard-schedule | rate(15 minutes) | Security Guard Lambda |
| w6-personal-cost-guard-schedule | cron(0 14 * * ? *) | Cost Guard Lambda |

- [ ] Screenshot: EventBridge rules enabled

## 7. CloudWatch Dashboard

Dashboard name: `w6-personal-dashboard`

- [ ] Screenshot: dashboard with EC2 CPU, custom metrics, Lambda invocations

Console URL:

```
https://ap-southeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-1#dashboards:name=w6-personal-dashboard
```

## 8. CloudWatch Alarms

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| w6-personal-ssh-revoked | W6/Security / SSHRulesRevoked | > 0 |
| w6-personal-ec2-cpu-high | AWS/EC2 / CPUUtilization | > 80% |

- [ ] Screenshot: alarms list
- [ ] Screenshot (optional): alarm triggered after Security Guard run

## 9. IAM Least Privilege

- [ ] Screenshot: `w6-personal-security-guard-role` inline policy
- [ ] Screenshot: `w6-personal-cost-guard-role` inline policy

Brief note on least-privilege design:

```
(Security Guard: describe/revoke SG only + PutMetricData on W6/Security namespace)
(Cost Guard: describe instances + stop only Environment=dev tagged instances)
```

## 10. Cost Notes

| Resource | Estimated cost |
|----------|----------------|
| t3.micro EC2 | ~$0 (free tier) / ~$8/mo |
| Lambda (128 MB) | negligible |
| EventBridge | negligible |
| CloudWatch | minimal |

Actions taken to minimize cost:

- Default VPC (no NAT Gateway)
- t3.micro instance type
- Lambda 128 MB / 7-day log retention
- Cost Guard stops dev instances on schedule

## 11. Cleanup

```bash
terraform destroy
```

- [ ] All resources destroyed

---

## Quick commands for tomorrow (báo cáo)

Chạy trong PowerShell tại thư mục `d:\XBRAIN\aws-w6`:

```powershell
# 1. Kiểm tra Flask
curl.exe http://54.151.147.214/
curl.exe http://54.151.147.214/health

# 2. Security Guard demo (thêm SSH trước → invoke → kiểm tra SG)
aws ec2 authorize-security-group-ingress --group-id sg-0054be3091feeb65c --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ap-southeast-1
aws lambda invoke --function-name w6-personal-security-guard --region ap-southeast-1 out.json
Get-Content out.json

# 3. Cost Guard demo (instance phải đang running)
aws ec2 start-instances --instance-ids i-0ce721101becfddf4 --region ap-southeast-1
aws ec2 wait instance-running --instance-ids i-0ce721101becfddf4 --region ap-southeast-1
aws lambda invoke --function-name w6-personal-cost-guard --region ap-southeast-1 out.json
Get-Content out.json

# 4. Bật lại EC2 sau demo Cost Guard
aws ec2 start-instances --instance-ids i-0ce721101becfddf4 --region ap-southeast-1
```

**Submission checklist**

- [ ] EC2 + Flask
- [ ] Security Guard Lambda + evidence
- [ ] Cost Guard Lambda + evidence
- [ ] EventBridge schedules
- [ ] CloudWatch Dashboard
- [ ] CloudWatch Alarm + custom metric
- [ ] IAM policies
- [ ] This evidence document completed
