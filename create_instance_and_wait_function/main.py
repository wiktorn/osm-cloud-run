import base64
import json
import typing

import googleapiclient.discovery
import time


# example message
# {
#     "project": "osm-vink",
#     "zone": "us-central1-c",
#     "name": "overpass-update",
#     "machine_type": "n1-standard-1",
#     "machine_label": "overpass_update",
#     "script_url_base": "gs://vink-osm-startup-scripts-us/overpass/update/",
#     "disk_size": "10",
#     "local_ssd": true
# }


class ContextType(typing.NamedTuple):
    event_id: str  # A unique ID for the event. For example "70172329041928"
    timestamp: str  # The date/time this event was created. For example: "2018-04-09T07:56:12.975Z". 	String (ISO 8601)
    event_type: str  # The type of the event. For example: "google.pubsub.topic.publish"
    resource: str  # The resource that emitted the event.


def create_instance_and_wait(data: dict, context: ContextType):
    """Background Cloud Function to be triggered by Pub/Sub.
    Args:
         data (dict): The dictionary with data specific to this type of event.
         context (google.cloud.functions.Context): The Cloud Functions event
         metadata.
    """

    compute = googleapiclient.discovery.build("compute", "v1")

    if "data" not in data:
        raise ValueError("Malformed input, no data sent. Input: %s" % data)
    if not isinstance(data["data"], str):
        raise ValueError("Malformed input, data not of type str. Input: %s" % data)
    data = json.loads(base64.b64decode(data["data"]).decode("utf-8"))

    project = data["project"]
    zone = data["zone"]
    operation = create_instance(
        compute=compute,
        project=project,
        zone=zone,
        name=data["name"],
        machine_type=data["machine_type"],
        script_url_base=data["script_url_base"],
        machine_label=data["machine_label"],
        disk_size=data.get("disk_size", "10"),
        local_ssd=data.get("local_ssd", False),
    )
    wait_for_operation(
        compute=compute, project=project, zone=zone, operation=operation["name"]
    )


def create_instance(
    *,
    compute: googleapiclient.discovery.Resource,
    project,
    zone,
    name,
    machine_type,
    script_url_base,
    machine_label,
    disk_size,
    local_ssd: bool,
):
    # Get the latest Ubuntu image
    image_response = (
        compute.images()
        .getFromFamily(project="ubuntu-os-cloud", family="ubuntu-minimal-1804-lts")
        .execute()
    )
    source_disk_image = image_response["selfLink"]

    # Configure the machine
    machine_type = f"zones/{zone}/machineTypes/{machine_type}"

    startup_script_url = script_url_base + "startup.sh"
    shutdown_script_url = script_url_base + "shutdown.sh"

    config = {
        "name": name,
        "machineType": machine_type,
        # Specify the boot disk and the image to use as a source.
        "disks": [
            {
                "boot": True,
                "autoDelete": True,
                "initializeParams": {
                    "sourceImage": source_disk_image,
                    "diskType": f"projects/{project}/zones/{zone}/diskTypes/pd-ssd",
                    "diskSizeGb": disk_size,
                },
            }
        ],
        # Specify a network interface with NAT to access the public
        # internet.
        "networkInterfaces": [
            {
                "network": "global/networks/default",
                "accessConfigs": [{"type": "ONE_TO_ONE_NAT", "name": "External NAT"}],
            }
        ],
        # Allow the instance to access cloud storage and logging.
        "serviceAccounts": [
            {
                "email": "compute-engine@osm-vink.iam.gserviceaccount.com",
                "scopes": ["https://www.googleapis.com/auth/cloud-platform"],
            }
        ],
        "scheduling": {"preemptible": True},
        "deleteProtection": False,
        # Metadata is readable from the instance and allows you to
        # pass configuration from deployment scripts to instances.
        "metadata": {
            "items": [
                {"key": "startup-script-url", "value": startup_script_url},
                {"key": "shutdown-script-url", "value": shutdown_script_url},
            ]
        },
        "labels": {"machine_type": machine_label},
    }

    if local_ssd:
        config["disks"].append(
            {
                "kind": "compute#attachedDisk",
                "mode": "READ_WRITE",
                "autoDelete": True,
                "deviceName": "local-ssd-0",
                "type": "SCRATCH",
                "interface": "NVME",
                "initializeParams": {
                    "diskType": f"projects/{project}/zones/{zone}/diskTypes/local-ssd"
                },
            }
        )

    return compute.instances().insert(project=project, zone=zone, body=config).execute()


def wait_for_operation(
    *, compute: googleapiclient.discovery.Resource, project, zone, operation
):
    print("Waiting for operation to finish...")
    while True:
        result = (
            compute.zoneOperations()
            .get(project=project, zone=zone, operation=operation)
            .execute()
        )

        if result["status"] == "DONE":
            print("done.")
            if "error" in result:
                raise Exception(result["error"])
            return result

        time.sleep(1)
