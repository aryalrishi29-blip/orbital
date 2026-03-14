#!/usr/bin/env bash
# =============================================================
# Create CloudWatch alarms for the Django application.
#
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - SNS topic created for alert notifications
#
# Usage:
#   INSTANCE_ID=i-0abc123 SNS_ARN=arn:aws:sns:... bash monitoring/alarms.sh
# =============================================================
set -euo pipefail

INSTANCE_ID="${INSTANCE_ID:?Set INSTANCE_ID env var}"
SNS_ARN="${SNS_ARN:?Set SNS_ARN env var (SNS topic for alerts)}"
REGION="${AWS_REGION:-us-east-1}"

echo "Creating CloudWatch alarms for instance: $INSTANCE_ID"

# ── CPU > 80% for 5 minutes ───────────────────────────────────
aws cloudwatch put-metric-alarm \
  --alarm-name        "orbital-cpu-high" \
  --alarm-description "EC2 CPU utilisation above 80% for 5 minutes" \
  --namespace         "AWS/EC2" \
  --metric-name       "CPUUtilization" \
  --dimensions        "Name=InstanceId,Value=$INSTANCE_ID" \
  --statistic         "Average" \
  --period            300 \
  --evaluation-periods 1 \
  --threshold         80 \
  --comparison-operator "GreaterThanThreshold" \
  --alarm-actions     "$SNS_ARN" \
  --ok-actions        "$SNS_ARN" \
  --region            "$REGION"
echo "  ✅ CPU alarm created"

# ── Memory > 85% for 5 minutes (requires CloudWatch Agent) ────
aws cloudwatch put-metric-alarm \
  --alarm-name        "orbital-memory-high" \
  --alarm-description "EC2 memory utilisation above 85% for 5 minutes" \
  --namespace         "CWAgent" \
  --metric-name       "mem_used_percent" \
  --dimensions        "Name=InstanceId,Value=$INSTANCE_ID" \
  --statistic         "Average" \
  --period            300 \
  --evaluation-periods 1 \
  --threshold         85 \
  --comparison-operator "GreaterThanThreshold" \
  --alarm-actions     "$SNS_ARN" \
  --ok-actions        "$SNS_ARN" \
  --region            "$REGION"
echo "  ✅ Memory alarm created"

# ── Disk > 80% ────────────────────────────────────────────────
aws cloudwatch put-metric-alarm \
  --alarm-name        "orbital-disk-high" \
  --alarm-description "EC2 root disk usage above 80%" \
  --namespace         "CWAgent" \
  --metric-name       "disk_used_percent" \
  --dimensions        "Name=InstanceId,Value=$INSTANCE_ID" \
                      "Name=path,Value=/" \
                      "Name=fstype,Value=xfs" \
  --statistic         "Average" \
  --period            300 \
  --evaluation-periods 1 \
  --threshold         80 \
  --comparison-operator "GreaterThanThreshold" \
  --alarm-actions     "$SNS_ARN" \
  --region            "$REGION"
echo "  ✅ Disk alarm created"

# ── Status check failure (instance unreachable) ───────────────
aws cloudwatch put-metric-alarm \
  --alarm-name        "orbital-instance-status" \
  --alarm-description "EC2 instance or system status check failed" \
  --namespace         "AWS/EC2" \
  --metric-name       "StatusCheckFailed" \
  --dimensions        "Name=InstanceId,Value=$INSTANCE_ID" \
  --statistic         "Maximum" \
  --period            60 \
  --evaluation-periods 2 \
  --threshold         1 \
  --comparison-operator "GreaterThanOrEqualToThreshold" \
  --alarm-actions     "$SNS_ARN" \
  --ok-actions        "$SNS_ARN" \
  --region            "$REGION"
echo "  ✅ Instance status alarm created"

echo ""
echo "All alarms created. Alerts will notify: $SNS_ARN"
echo "View in AWS Console: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#alarmsV2:"
