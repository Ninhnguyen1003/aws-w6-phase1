"""Cost Guard Lambda – stop EC2 instances tagged Environment=dev."""

import os
from datetime import datetime, timezone

import boto3

ec2 = boto3.client("ec2")
cloudwatch = boto3.client("cloudwatch")

ENVIRONMENT_TAG = os.environ.get("ENVIRONMENT_TAG", "dev")
METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "W6/Cost")
METRIC_NAME = os.environ.get("METRIC_NAME", "InstancesStopped")


def _publish_metric(stopped_count: int) -> None:
    if stopped_count <= 0:
        return
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[{
            "MetricName": METRIC_NAME,
            "Value": stopped_count,
            "Unit": "Count",
            "Timestamp": datetime.now(timezone.utc),
        }],
    )


def handler(event, context):
    response = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Environment", "Values": [ENVIRONMENT_TAG]},
            {"Name": "instance-state-name", "Values": ["running", "pending"]},
        ]
    )

    instance_ids = []
    for reservation in response.get("Reservations", []):
        for instance in reservation.get("Instances", []):
            instance_ids.append(instance["InstanceId"])

    stopped = []
    if instance_ids:
        stop_response = ec2.stop_instances(InstanceIds=instance_ids)
        stopped = [
            change["InstanceId"]
            for change in stop_response.get("StoppingInstances", [])
        ]

    _publish_metric(len(stopped))

    result = {
        "environment_tag": ENVIRONMENT_TAG,
        "stopped_count": len(stopped),
        "stopped_instance_ids": stopped,
    }
    print(result)
    return result
