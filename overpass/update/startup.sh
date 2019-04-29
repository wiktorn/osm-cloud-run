#!/usr/bin/env sh


(
    set -e
    apt update
    apt install -y docker.io google-cloud-sdk git python3 python3-venv
    gcloud auth configure-docker -q
    gcloud docker -- run  --name overpass_step1 \
            -e OVERPASS_META=yes \
            -e OVERPASS_MODE=init \
            -e OVERPASS_PLANET_URL=http://download.geofabrik.de/europe/poland-latest.osm.bz2 \
            -e OVERPASS_DIFF_URL=http://download.geofabrik.de/europe/poland-updates/ \
            -e OVERPASS_COMPRESSION=gz \
            -i \
            gcr.io/osm-vink/overpass-poland:latest \
            /bin/bash -c "/app/bin/update_overpass.sh && /app/bin/osm3s_query --progress --rules --rules --db-dir=/db/db < /db/db/rules/areas.osm3s"
    docker commit --change 'CMD /app/docker-entrypoint.sh' overpass_step1 gcr.io/osm-vink/overpass-poland:latest
    python3 -m venv /venv
    /venv/bin/pip install docker-squash
    # FROM_LAYER=`docker images gcr.io/osm-vink/overpass-poland | grep gcr.io/osm-vink/overpass-poland | grep -v latest | awk '{print $3}'`
    /venv/bin/docker-squash -t latest -c gcr.io/osm-vink/overpass-poland:latest
    gcloud docker -- push gcr.io/osm-vink/overpass-poland:latest
    gcloud beta run deploy overpass-poland \
            --image=gcr.io/osm-vink/overpass-poland:latest \
            --region=us-central1 \
            --memory=1024Mi \
            --allow-unauthenticated
    for SHA in `gcloud container images list-tags --filter='NOT tags=latest' gcr.io/osm-vink/overpass-poland --format='get(digest)'`
    do
        gcloud container images delete --quiet gcr.io/osm-vink/overpass-poland@$SHA
    done
) | gsutil cp - gs://vink-osm-startup-scripts-us/overpass/update.log

gcloud compute instances list --filter 'labels.machine_type=overpass_update' --uri | xargs gcloud compute instances delete --quiet
