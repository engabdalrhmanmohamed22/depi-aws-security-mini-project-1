"""
Task 17 — Auto-remediation of an open SSH/RDP rule.

Triggered by an EventBridge rule that matches CloudTrail's
AuthorizeSecurityGroupIngress events (source: aws.ec2). If anybody opens
port 22 (SSH) or 3389 (RDP) to 0.0.0.0/0 on any security group, this
function revokes that specific rule immediately and publishes a
notification to SNS.

Detection tells you about the problem. Remediation removes it. A human
takes minutes or hours; this takes seconds, and it never sleeps.
"""

import os
import boto3

DANGEROUS_PORTS = {22, 3389}
DANGEROUS_CIDR = "0.0.0.0/0"


def handler(event, context):
    ec2 = boto3.client("ec2")
    sns = boto3.client("sns")

    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})
    group_id = request_params.get("groupId")

    if not group_id:
        print("No groupId found in event — nothing to do.")
        return {"revoked": []}

    ip_permissions = request_params.get("ipPermissions", {}).get("items", [])
    revoked = []

    for perm in ip_permissions:
        from_port = perm.get("fromPort")
        to_port = perm.get("toPort")
        protocol = perm.get("ipProtocol")
        ip_ranges = perm.get("ipRanges", {}).get("items", [])

        is_dangerous_port = (
            from_port in DANGEROUS_PORTS or to_port in DANGEROUS_PORTS
        )

        for ip_range in ip_ranges:
            cidr = ip_range.get("cidrIp")

            if cidr == DANGEROUS_CIDR and is_dangerous_port:
                try:
                    ec2.revoke_security_group_ingress(
                        GroupId=group_id,
                        IpPermissions=[
                            {
                                "IpProtocol": protocol,
                                "FromPort": from_port,
                                "ToPort": to_port,
                                "IpRanges": [{"CidrIp": cidr}],
                            }
                        ],
                    )
                    description = f"port {from_port}-{to_port} ({protocol}) from {cidr}"
                    revoked.append(description)
                    print(f"Revoked on {group_id}: {description}")
                except Exception as exc:  # noqa: BLE001 — log and continue
                    print(f"Failed to revoke rule on {group_id}: {exc}")

    if revoked:
        topic_arn = os.environ["SNS_TOPIC_ARN"]
        message = (
            f"Auto-remediation fired on security group {group_id}.\n\n"
            f"Revoked rule(s):\n- " + "\n- ".join(revoked)
        )
        sns.publish(
            TopicArn=topic_arn,
            Subject="[depi-sec] Auto-remediation: dangerous inbound rule revoked",
            Message=message,
        )
        print("SNS notification published.")

    return {"revoked": revoked}
