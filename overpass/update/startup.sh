#!/usr/bin/env bash


(
    set -e
    echo "Starting update"
    date

    # install agent
    curl -sSO https://dl.google.com/cloudagents/install-logging-agent.sh
    bash install-logging-agent.sh


    # mount local ssd
    mkfs.ext4 /dev/nvme0n1
    mkdir /var/lib/docker
    mount /dev/nvme0n1 /var/lib/docker/

    # install software
    apt update
    apt install -y docker.io git python3 python3-venv
    gcloud auth configure-docker -q

    gcloud docker -- run  --name overpass_step1 \
            -e OVERPASS_META=yes \
            -e OVERPASS_MODE=init \
            -e OVERPASS_PLANET_URL=http://download.geofabrik.de/europe/poland-latest.osm.bz2 \
            -e OVERPASS_DIFF_URL=http://download.geofabrik.de/europe/poland-updates/ \
            -e OVERPASS_COMPRESSION=gz \
            -i \
            gcr.io/osm-vink/overpass-poland:latest \
            /bin/bash -c "/app/bin/update_overpass.sh"

    docker commit --change 'CMD /app/docker-entrypoint.sh' overpass_step1 gcr.io/osm-vink/overpass-poland:latest
    docker rm overpass_step1

    # squash image
    python3 -m venv /venv
    /venv/bin/pip install docker-squash
    # FROM_LAYER=`docker images gcr.io/osm-vink/overpass-poland | grep gcr.io/osm-vink/overpass-poland | grep -v latest | awk '{print $3}'`
    export DOCKER_TIMEOUT=6000
    # /venv/bin/docker-squash -t gcr.io/osm-vink/overpass-poland:squashed -c gcr.io/osm-vink/overpass-poland:latest
    # /venv/bin/docker-squash -c gcr.io/osm-vink/overpass-poland:latest
    # /venv/bin/docker-squash -t squashed -c gcr.io/osm-vink/overpass-poland:latest
    /venv/bin/docker-squash --tmp-dir /var/lib/docker/tmp/docker-squash gcr.io/osm-vink/overpass-poland:latest

    NEW_IMAGE=$(docker images -a --format '{{.Repository}}:{{.ID}}' | grep -v gcr.io | awk -F ':' '{print $2}')
    docker tag $NEW_IMAGE gcr.io/osm-vink/overpass-poland:latest

    # upload image
    gcloud docker -- push gcr.io/osm-vink/overpass-poland:latest

    # deploy on Cloud Run
    gcloud beta run deploy overpass-poland \
            --async \
            --image=gcr.io/osm-vink/overpass-poland:latest \
            --region=us-central1 \
            --memory=1024Mi \
            --allow-unauthenticated

    # Cleanup older images
    for SHA in `gcloud container images list-tags --filter='NOT tags=latest' gcr.io/osm-vink/overpass-poland --format='get(digest)'`
    do
        gcloud container images delete --quiet gcr.io/osm-vink/overpass-poland@$SHA
    done
    echo "Finished update"
    date
    echo "Overpass update duration: ${SECONDS}"
)

gcloud compute instances list --filter 'labels.machine_type=overpass_update' --uri | xargs gcloud compute instances delete --quiet

# trigger
# $ gcloud pubsub topics publish osm-vink-scheduled-instances --message '{"project": "osm-vink","zone": "us-central1-c","name": "overpass-update","machine_type": "n1-highcpu-2","machine_label": "overpass_update","script_url_base": "gs://vink-osm-startup-scripts-us/overpass/update/","disk_size": "10","local_ssd": true}'
