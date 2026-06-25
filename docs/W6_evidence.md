# W6 Evidence – AWS Security & Cost Automation

> Personal AWS W6 project – `ap-southeast-1`

---

## 1. Student / Project Info

| Field | Value |
|-------|-------|
| Name | Nguyen Quach Khang Ninh |
| Student ID | XB-DN26-014 |
| Region | ap-southeast-1 |
| Project prefix | w6-personal |
| Key pair | ninh_dev |
| Deploy date | 2026-06-25 |

---

## 2. Architecture Overview

![AWS Architecture Flow](docs/image/w6_aws_architecture_flow.png)
```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS ap-southeast-1                       │
│                                                                 │
│  ┌──────────────┐     HTTP:80      ┌─────────────────────────┐  │
│  │   Internet   │ ──────────────▶ │  EC2 t3.micro           │  │
│  │   (Public)   │                 │  w6-personal-flask       │  │
│  └──────────────┘                 │  Flask / Gunicorn        │  │
│                                   │  Tag: Environment=dev    │  │
│  ┌──────────────────────────────────────────────────────────┐ │  │
│  │ EventBridge                                              │ │  │
│  │  ┌──────────────────────┐  ┌───────────────────────────┐│ │  │
│  │  │ rate(15 min)         │  │ cron(0 14 * * ? *)        ││ │  │
│  │  └─────────┬────────────┘  └────────────┬──────────────┘│ │  │
│  └────────────┼───────────────────────────┼───────────────┘ │  │
│               ▼                           ▼                  │  │
│  ┌────────────────────────┐  ┌────────────────────────────┐  │  │
│  │ Lambda                 │  │ Lambda                     │  │  │
│  │ w6-personal-           │  │ w6-personal-               │  │  │
│  │ security-guard         │  │ cost-guard                 │  │  │
│  │                        │  │                            │  │  │
│  │ Revoke SSH 0.0.0.0/0   │  │ Stop dev EC2 instances     │  │  │
│  └────────────┬───────────┘  └────────────┬───────────────┘  │  │
│               │                           │                  │  │
│               ▼ PutMetricData             ▼ PutMetricData     │  │
│  ┌──────────────────────────────────────────────────────────┐  │  │
│  │ CloudWatch                                               │  │  │
│  │  Namespace W6/Security  │  Namespace W6/Cost             │  │  │
│  │  Metric: SSHRulesRevoked│  Metric: InstancesStopped      │  │  │
│  │                                                          │  │  │
│  │  Alarm: w6-personal-ssh-revoked  (> 0)                   │  │  │
│  │  Alarm: w6-personal-ec2-cpu-high (> 80%)                 │  │  │
│  │  Dashboard: w6-personal-dashboard                        │  │  │
│  └──────────────────────────────────────────────────────────┘  │  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Deployment Evidence

### 3.1 Terraform apply

```bash
cd aws-w6
terraform init
terraform plan
terraform apply
```

**Summary:**

```
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.
```

> **Lưu ý:** Account chưa có default VPC → đã chạy `aws ec2 create-default-vpc --region ap-southeast-1` trước khi apply.

### 3.2 Key outputs

| Output | Value |
|--------|-------|
| EC2 instance ID | `i-0ce721101becfddf4` |
| Public IP | `54.151.147.214` *(thay đổi sau stop/start)* |
| Flask URL | `http://54.151.147.214` |
| Security group ID | `sg-0054be3091feeb65c` |
| Dashboard URL | https://ap-southeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-1#dashboards:name=w6-personal-dashboard |

---

## 4. EC2 + Flask App

### 4.1 Instance running

![Instance Running](docs/image/Instance_running.png)

### 4.2 Flask app accessible

```bash
curl http://54.151.147.214/
curl http://54.151.147.214/health
```

**Expected response:**

```
<h1>W6 Flask App</h1><p>AWS Week 6 – ap-southeast-1</p>
{"service":"w6-flask","status":"ok"}
```

![Browser](docs/image/browser.png)`

### 4.3 Flask setup (user_data)

Flask được cài đặt tự động qua `flask_setup.sh` khi EC2 khởi động:

- Cài `python3`, `pip3`, `flask`, `gunicorn` qua `dnf`
- App đặt tại `/opt/flask-app/app.py`
- Chạy bằng `gunicorn` bind `0.0.0.0:80`, 1 worker
- Quản lý bởi `systemd` service (`flask.service`), tự restart khi lỗi

---

## 5. Security Guard Lambda

### 5.1 Mô tả chức năng

Lambda `w6-personal-security-guard` tự động quét toàn bộ Security Groups trong tài khoản. Với mỗi rule ingress có CIDR `0.0.0.0/0` trên port 22 (SSH), Lambda sẽ revoke rule đó và đẩy metric lên CloudWatch.

**Logic kiểm tra rule (`lambda_function.py`):**

```python
def _is_open_ssh_rule(rule: dict) -> bool:
    if rule.get("IsEgress"):           # Bỏ qua egress
        return False
    if rule.get("CidrIpv4") != "0.0.0.0/0":  # Chỉ xét CIDR mở
        return False
    protocol = rule.get("IpProtocol")
    if protocol in ("-1", "all"):      # All-traffic rule cũng bị revoke
        return True
    if protocol not in ("tcp", "6"):
        return False
    return rule["FromPort"] <= 22 <= rule["ToPort"]
```

### 5.2 Open SSH rule (before)

Thêm rule SSH mở để demo:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0054be3091feeb65c \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --region ap-southeast-1
```


### 5.3 Lambda invocation

```bash
aws lambda invoke \
  --function-name w6-personal-security-guard \
  --region ap-southeast-1 \
  out.json && cat out.json
```

**Response:**

```json
{
  "revoked_count": 1,
  "revoked_rules": [
    {
      "GroupId": "sg-0054be3091feeb65c",
      "GroupName": "w6-personal-flask-sg",
      "RuleId": "sgr-05f5407bf28fc4359"
    }
  ]
}
```
![Lambda](docs/image/lambda.png)

### 5.4 Rule revoked (after)

![SSH_Rule](docs/image/SG_rule SSH.png)
![Cloud Metric](docs/image/CloudWatch_metric.png)
![Cloud Metric tăng](docs/image/Alarm.png)
---

## 6. Cost Guard Lambda

### 6.1 Mô tả chức năng

Lambda `w6-personal-cost-guard` dừng tất cả EC2 instances có tag `Environment=dev` đang ở trạng thái `running`. Sau khi stop, Lambda đẩy metric `InstancesStopped` lên CloudWatch namespace `W6/Cost`.

### 6.2 Instance running with tag

- [ ] **Screenshot:** EC2 `w6-personal-flask` – state `running`, tag `Environment=dev` visible

### 6.3 Lambda invocation

```bash
aws lambda invoke \
  --function-name w6-personal-cost-guard \
  --region ap-southeast-1 \
  out.json && cat out.json
```

**Response:**

```json
{
  "environment_tag": "dev",
  "stopped_count": 1,
  "stopped_instance_ids": ["i-0ce721101becfddf4"]
}
```

### 6.4 Instance stopped

> Khởi động lại instance sau demo:
> ```bash
> aws ec2 start-instances --instance-ids i-0ce721101becfddf4 --region ap-southeast-1
> ```

---

## 7. EventBridge Schedules

| Rule | Schedule | Target |
|------|----------|--------|
| `w6-personal-security-guard-schedule` | `rate(15 minutes)` | Lambda: security-guard |
| `w6-personal-cost-guard-schedule` | `cron(0 14 * * ? *)` | Lambda: cost-guard |

- Security Guard chạy **mỗi 15 phút** để liên tục kiểm tra SG.
- Cost Guard chạy **hàng ngày lúc 14:00 UTC** (21:00 ICT) để dừng dev instances.


---

## 8. CloudWatch Dashboard

**Dashboard name:** `w6-personal-dashboard`

**Widgets bao gồm:**
- EC2 CPUUtilization (`i-0ce721101becfddf4`)
- Custom metric `W6/Security / SSHRulesRevoked`
- Custom metric `W6/Cost / InstancesStopped`
- Lambda invocation count (security-guard & cost-guard)

**Console URL:**
```
https://ap-southeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-1#dashboards:name=w6-personal-dashboard
```

---

## 9. CloudWatch Alarms

| Alarm | Metric | Threshold | Ý nghĩa |
|-------|--------|-----------|---------|
| `w6-personal-ssh-revoked` | `W6/Security / SSHRulesRevoked` | > 0 | Phát hiện SSH rule mở bị revoke |
| `w6-personal-ec2-cpu-high` | `AWS/EC2 / CPUUtilization` | > 80% | EC2 CPU quá tải |

![Cloudwatch alarm](docs/image/CloudWatch_Alarms.png)
![Alarm Details](docs/image/alarm_details.png)
---

## 10. IAM Least Privilege

### Security Guard Role (`w6-personal-security-guard-role`)

**Inline policy cho phép:**
- `ec2:DescribeSecurityGroups` – liệt kê tất cả SG
- `ec2:DescribeSecurityGroupRules` – đọc inbound rules
- `ec2:RevokeSecurityGroupIngress` – xóa rule vi phạm
- `cloudwatch:PutMetricData` – ghi metric **chỉ** vào namespace `W6/Security`

**Không có:** quyền tạo/xóa SG, modify instances, S3, IAM, hay bất kỳ resource nào khác.

### Cost Guard Role (`w6-personal-cost-guard-role`)

**Inline policy cho phép:**
- `ec2:DescribeInstances` – tìm instances theo tag
- `ec2:StopInstances` với điều kiện `aws:ResourceTag/Environment = dev` – chỉ stop instances có tag dev
- `cloudwatch:PutMetricData` – ghi metric **chỉ** vào namespace `W6/Cost`

**Không có:** quyền terminate instances, start instances, hay tác động đến production resources.

![Policy Roles](docs/image/roles.png)
---

## 11. Cost Notes

| Resource | Ước tính chi phí |
|----------|-----------------|
| EC2 t3.micro | ~$0 (free tier 750h/tháng) / ~$8/tháng nếu hết free tier |
| Lambda (128 MB) | Không đáng kể (< triệu lần gọi/tháng miễn phí) |
| EventBridge | Không đáng kể |
| CloudWatch | Tối thiểu (< 10 metrics, < 10 alarms) |

**Các biện pháp tiết kiệm chi phí:**
- Dùng Default VPC → không cần NAT Gateway (tiết kiệm ~$32/tháng)
- Instance type `t3.micro` – nằm trong free tier
- Lambda memory 128 MB, log retention 7 ngày
- Cost Guard tự động dừng dev instances lúc 14:00 UTC hàng ngày

---

## 12. Cleanup

```bash
terraform destroy
```

- [ ] Xác nhận tất cả 19 resources đã bị destroy

---

## Submission Checklist

- [ ] EC2 + Flask app accessible
- [ ] Security Guard Lambda + evidence (before/after screenshots)
- [ ] Cost Guard Lambda + evidence (before/after screenshots)
- [ ] EventBridge schedules enabled
- [ ] CloudWatch Dashboard với đủ widgets
- [ ] CloudWatch Alarms + custom metrics
- [ ] IAM least-privilege policies
- [ ] Evidence document hoàn chỉnh (file này)