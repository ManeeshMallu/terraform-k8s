#!/usr/bin/env python3
import json
import requests
from flask import Flask, request
from datetime import datetime, timedelta
import os

app = Flask(__name__)

LOKI_URL = "http://localhost:3100"
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"


def query_loki_logs(instance_label, minutes_before=10):
    """Pull recent logs for the affected service from loki"""
    end = datetime.now()
    start = end - timedelta(minutes=minutes_before)

    params = {
        "query": f'{{job="apache", instance="{instance_label}"}}',
        "start": int(start.timestamp() * 1e9),
        "end": int(end.timestamp() * 1e9),
        "limit": 100,
    }

    try:
        resp = requests.get(f"{LOKI_URL}/loki/api/v1/query_range", params=params, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        logs = []
        for stream in data.get("data", {}).get("result", []):
            for entry in stream.get("values", []):
                logs.append(entry[1])
        return "\n".join(logs[-50:])
    except requests.RequestException as e:
        return f"[Could not retrieve logs: {e}]"

def ask_claude_for_diagnosis(alert_name, alert_labels, alert_annotations, logs):
    """Send alert context + logs to Claude for a root-cause hypothesis"""
    prompt = f"""You are assisting an SRE with incident triage. An alert just fired.

Alert: {alert_name}
Labels: {json.dump(alert_labels, indent=2)}
Annotations: {json.dumps(alert_annotations, indent=2)}

Recent logs from the affected service:
{logs}

Provide:
1. A likely root cause hypothesis (1 - 2 sentences)
2. Severity assessment (low/med/high) with brief reasoning
3. One concrete next diagnostic step for the on-call engineer

Keep it concise - this will be posted to a Slack channel."""

    headers = {
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = {
        "model": "claude-sonnet-4-5",
        "max_tokens": 400,
        "messages": [{"role": "user", "content": prompt}],
    }

    try:
        resp = requests.post(ANTHROPIC_URL, headers=headers, json=payload, timeout=15)
        resp.raise_for_status()
        return resp.json()["content"][0]["text"]
    except requests.RequestException as e:
        return f"[AI diagnosis unavailable: {e}]"

@app.route("/alert", methods=["POST"])
def handle_alert():
    payload = request.json
    results = []

    for alert in payload.get("alerts", []):
        alert_name = alert["labels"].get("alertname", "Unknown")
        instance = alert["labels"].get("instance","")

        print(f"[{datetime.utcnow().isoformat()}] Alert fired: {alert_name} on {instance}")

        logs = query_loki_logs(instance)
        diagnosis = ask_claude_for_diagnosis(
            alert_name, alert["labels"], alert.get("annotations", {}), logs
        )

        result = {
            "alert": alert_name,
            "instance": instance,
            "diagnosis": diagnosis,
        }
        results.append(result)

        print(f"--- AI Diagnosis for {alert_name} ---")
        print(diagnosis)
        print("---")

    return json.dumps({"status": "processed", "results": results}), 200


if __name__ == "__main__":
   app.run(host="0.0.0.0", port=5001)   
