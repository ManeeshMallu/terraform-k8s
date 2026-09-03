import paramiko
import sys
import os
from dotenv import load_dotenv

load_dotenv()

def check_server_health(server_ips, username, password_or_key):
    # create a reusable SSH client instance
    ssh = paramiko.SSHClient()

    # Automatically add unknown host keys
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    print(f"Starting automation sweep across {len(server_ips)} infra\n")

    # loop through our server fleet
    for ip in server_ips:
        print(f"Attempting to connecting to: {ip}...")
        
        try:
            # connect to the remote instance
            #Note: In a mock test, this will attempt a real network connection
            # to simulate a timeout cleanly without scaling
            ssh.connect(hostname=ip, username=username, password=password_or_key, timeout=3)

            command = "uptime && df -h /"
            stdin, stderr, stdout = ssh.exec_command(command)

            # read the output text from the stdout
            output = stdout.read().decode('utf-8')
            error  = stderr.read().decode('utf-8')

            if error:
                print(f"Error running command on {ip}: {error}")
            else:
                print(f"Success from {ip}:")
                print(output)

            ssh.close()

        except paramiko.AuthenticationException:
            print(f"Critical: Authentication failed for {ip}. Check creds.")
        except paramiko.SSHException as e:
            print(f"Critical: SSH protocol failure on {ip}: {e}")
        except Exception as e:
            print(f"Critical: Failed to reach host {ip}. Network Error: {e}")

        print("-" * 50)

if __name__ == "__main__":

    target_hosts = ["192.168.1.50", "10.0.0.12", "8.8.8.8"]

    secure_password = os.getenv("SSH_PASSWORD")

    if not secure_password:
        print("Critical Failure: the 'SSH_PASSWORD' environment variables")
        print("Please set it in your terminal before executing this automation tool.")
        sys.exit(1)

    check_server_health(
        server_ips=target_hosts,
        username="admin",
        password_or_key=secure_password
    )
