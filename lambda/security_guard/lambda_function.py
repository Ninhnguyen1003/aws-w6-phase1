"""Security Guard Lambda – revoke Security Group SSH rules open to 0.0.0.0/0."""

import os
from datetime import datetime, timezone

import boto3

ec2 = boto3.client("ec2")
cloudwatch = boto3.client("cloudwatch")

METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "W6/Security")
METRIC_NAME = os.environ.get("METRIC_NAME", "SSHRulesRevoked")
OPEN_CIDR = "0.0.0.0/0"
SSH_PORT = 22


def _is_open_ssh_rule(rule: dict) -> bool:
    if rule.get("IsEgress"):
        return False
    if rule.get("CidrIpv4") != OPEN_CIDR:
        return False

    protocol = rule.get("IpProtocol")
    if protocol in ("-1", "all"):
        return True
    if protocol not in ("tcp", "6"):
        return False

    from_port = rule.get("FromPort")
    to_port = rule.get("ToPort")
    if from_port is None or to_port is None:
        return False
    return from_port <= SSH_PORT <= to_port


def _revoke_rule(group_id: str, rule: dict) -> None:
    rule_id = rule.get("SecurityGroupRuleId")
    if rule_id:
        ec2.revoke_security_group_ingress(
            GroupId=group_id,
            SecurityGroupRuleIds=[rule_id],
        )
        return

    ip_permissions = [{
        "IpProtocol": rule.get("IpProtocol", "tcp"),
        "FromPort": rule.get("FromPort", SSH_PORT),
        "ToPort": rule.get("ToPort", SSH_PORT),
        "IpRanges": [{"CidrIp": OPEN_CIDR}],
    }]
    ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=ip_permissions)


def _publish_metric(revoked_count: int) -> None:
    if revoked_count <= 0:
        return
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[{
            "MetricName": METRIC_NAME,
            "Value": revoked_count,
            "Unit": "Count",
            "Timestamp": datetime.now(timezone.utc),
        }],
    )


def handler(event, context):
    revoked = []

    sg_paginator = ec2.get_paginator("describe_security_groups")
    rule_paginator = ec2.get_paginator("describe_security_group_rules")

    for page in sg_paginator.paginate():
        for sg in page.get("SecurityGroups", []):
            group_id = sg["GroupId"]
            for rules_page in rule_paginator.paginate(
                Filters=[{"Name": "group-id", "Values": [group_id]}]
            ):
                for rule in rules_page.get("SecurityGroupRules", []):
                    if _is_open_ssh_rule(rule):
                        _revoke_rule(group_id, rule)
                        revoked.append({
                            "GroupId": group_id,
                            "GroupName": sg.get("GroupName"),
                            "RuleId": rule.get("SecurityGroupRuleId"),
                        })

    _publish_metric(len(revoked))

    result = {
        "revoked_count": len(revoked),
        "revoked_rules": revoked,
    }
    print(result)
    return result
