import os
import urllib3
import time
import logging
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

# config structured logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - [%(levelname)s] - %(message)s')

def init_k8s_client():
    """Initializes the kubernetes client depending on execution environment."""
    try:
        # check if running inside a cluster container
        if os.path.exists("/var/run/secrets/kubernetes.io/serviceaccount/token"):
            config.load_incluster_config()
            logging.info("Initialized in-cluster kubernetes configuration")
        else:
            config.load_kube_config()
            logging.info("Initialized local kubeconfig configuration")
        return client.CoreV1Api()
    except Exception as e:
        logging.critical(f"Failed to initialize Kubernetes client: {e}")
        raise

def inspect_and_fix_pod(v1, pod_name, namespace):
    """Investigates a broken pod's logs and applies a self-healing action."""
    logging.warning(f"Investigating problematic pod: {pod_name} in namespace")

    try:
        # fetch logs
        # limit_bytes avoids overloading memory
        logs = v1.read_namespaced_pod_log(name=pod_name, namespace=namespace, limit_bytes=5000)
        logging.info(f"--- LOG SNIPPET FOR {pod_name} --- \n{logs}\n-----------------------")

        # Match errors and apply specific automated fixes
        if "Out of Memory" in logs or "OOMKilled" in logs:
           logging.error(f"Fix triggered: {pod_name} died due to OOM. Alerting engineering team...")
           # here you would typically integrate a webhook

        elif "Connection refused" in logs or "Deadlock" in logs or "CrashLoopBackoff" in logs:
           logging.warning(f"Fix triggered: App is stuck or deadlocked. Executing force restart on {pod_name}...")

           # Action: Delete the pod with 0 grace period so it immediately terminates
           # The deployment controller will automatically spin up a fresh replacement
           delete_options = client.V1DeleteOptions(grace_period_seconds=0)
           v1.delete_namespaced_pod(name=pod_name, namespace=namespace, body=delete_options)
           logging.info(f"Successfully deleted stuck pod {pod_name}. Controller is deploying a replacement.")

    except Exception as e:
        logging.error(f"Failed to execute self-healing sequence on {pod_name}: {e}")

def monitor_pods(namespace="default"):
    """Streams live pod events and catches structural failures."""
    v1 = init_k8s_client()
    w = watch.Watch()

    logging.info(f"Starting live monitoring loop for pods in namespace: '{namespace}' ...")

    while True:
        try:
            # infinite stream loop watching pod resource modifications
            for event in w.stream(v1.list_namespaced_pod, namespace=namespace):
                pod = event['object']
                pod_name = pod.metadata.name
                status = pod.status

                # check container status blocks for common infra errors
                if status.container_statuses:
                    for container_status in status.container_statuses:
                        state = container_status.state

                        # catch pods stuck in waiting loops
                        if state.waiting and state.waiting.reason in ["CrashLoopBackOff", "ImagePullBackOff"]:
                            logging.error(f"Detected pod alert! Name: {pod_name} | Reason: {state.waiting.reason}")
                            inspect_and_fix_pod(v1, pod_name, namespace)

                        # catch pods that completed with an unhandled exit
                        elif state.terminated and state.terminated.exit_code != 0:
                            logging.error(f"Detected pod alert! Name: {pod_name} | Terminated with exit code: {state.terminated.exit_code}")
                            inspect_and_fix_pod(v1, pod_name, namespace)
        except (urllib3.exceptions.NameResolutionError, urllib3.exceptions.MaxRetryError) as net_err:
            print(f"⚠️ Network Warning: Unable to resolve AWS cluster endpoint. Retrying in 10 seconds...")
            time.sleep(10)
            
        except ApiException as api_err:
            print(f"❌ K8s API Error: {api_err}")
            break

if __name__ == "__main__":
    # monitor the default namespace. Can be adjusted via env variables
    TARGET_NAMESPACE = os.getenv("HEALER_NAMESPACE", "default")
    monitor_pods(namespace=TARGET_NAMESPACE)
