#!/usr/bin/env sh

# assume gcloud is installed
# apt install -y google-cloud-sdk
(
    set -e
    echo "Starting init"
    date
    # install agent
    curl -sSO https://dl.google.com/cloudagents/install-logging-agent.sh
    bash install-logging-agent.sh

    # mount local SSD
    mkfs.ext4 /dev/nvme0n1
    mkdir /var/lib/docker
    mount /dev/nvme0n1 /var/lib/docker/

    # install git, docker
    apt update
    apt install -y docker.io git

    # prepare image
    docker run --name overpass_step1 \
        -e OVERPASS_META=yes \
        -e OVERPASS_MODE=init \
        -e OVERPASS_PLANET_URL=http://download.geofabrik.de/europe/poland-latest.osm.bz2 \
        -e OVERPASS_DIFF_URL=http://download.geofabrik.de/europe/poland-updates/ \
        -e OVERPASS_COMPRESSION=gz \
        -i \
        wiktorn/overpass-api \
        /bin/bash -c '/app/docker-entrypoint.sh'

    # get modifications
    mkdir /app
    cd /app
    git clone https://github.com/wiktorn/osm-cloud-run.git
    cd osm-cloud-run/overpass/init
    docker cp supervisord.conf overpass_step1:/etc/supervisor/supervisord.conf
    docker commit --change 'CMD /app/docker-entrypoint.sh' overpass_step1 gcr.io/osm-vink/overpass-poland:latest

    # upload image
    gcloud auth configure-docker -q
    gcloud docker -- push gcr.io/osm-vink/overpass-poland:latest

    # deploy on Cloud Run
    gcloud beta run deploy overpass-poland \
        --image=gcr.io/osm-vink/overpass-poland:latest \
        --region=us-central1 \
        --memory=1024Mi \
        --allow-unauthenticated

    # Cleanup older images
    for SHA in `gcloud container images list-tags --filter='NOT tags=latest' gcr.io/osm-vink/overpass-poland --format='get(digest)'`
    do
        gcloud container images delete --quiet gcr.io/osm-vink/overpass-poland@$SHA
    done
    echo "Finished init"
    date

) 2>1 | gsutil cp - gs://vink-osm-startup-scripts-us/overpass/init.log

gcloud compute instances list --filter 'labels.machine_type=overpass' --uri | xargs gcloud compute instances delete --quiet

#
# trigger
# $ gcloud pubsub topics publish osm-vink-scheduled-instances --message '{"project": "osm-vink","zone": "us-central1-c","name": "overpass-init","machine_type": "n1-standard-2","machine_label": "overpass","script_url_base": "gs://vink-osm-startup-scripts-us/overpass/init/","disk_size": "10","local_ssd": true}'
