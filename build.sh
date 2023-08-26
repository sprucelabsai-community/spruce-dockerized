set -e

scripts_dir="$HOME/.sprucebot"

write_script() {
    local script_name=$1
    local script_content=$2
    local script_file="$scripts_dir/$script_name"
    echo "$script_content" >"$script_file"
    chmod +x "$script_file"
}

DB_CONNECTION_STRING="mongodb://localhost:27017"
DATABASE_NAME="default"
SHOULD_SERVE_HEARTWOOD="true"
MERCURY_ENV="default"

# Parse arguments
for arg in "$@"; do
    case $arg in
    --databaseConnectionString=*)
        DB_CONNECTION_STRING="${arg#*=}"
        shift
        ;;
    --databaseName=*)
        DATABASE_NAME="${arg#*=}"
        shift
        ;;
    --shouldServeHeartwood=*)
        SHOULD_SERVE_HEARTWOOD="${arg#*=}"
        shift
        ;;
    --skillsEnvConfigPath=*)
        SKILLS_ENV_CONFIG_PATH="${arg#*=}"
        shift
        ;;
    --mercuryEnv=*)
        MERCURY_ENV="${arg#*=}"
        shift
        ;;
    *)
        shift
        ;;
    esac
done

curl -s -O -L https://github.com/stackdumper/npm-cache-proxy/releases/download/1.3.3/ncp_linux_amd64
chmod +x ncp_linux_amd64
./ncp_linux_amd64 --listen ":28080" &
NCP_PID=$!

# Create scripts directory
mkdir -p "$scripts_dir"

echo "SKILLS_ENV_CONFIG_PATH=$SKILLS_ENV_CONFIG_PATH"

# Write the scripts
echo "Writing boot-all-skills-forever script..."
cat <<EOF >"$scripts_dir/boot-all-skills-forever"
#!/usr/bin/env bash

screen_name="skills"
boot_command="bash $scripts_dir/boot-skill-forever"
echo "Starting boot all skills forever"
# Quit any existing screens with the same name
screen -S "\${screen_name}" -X quit

# Create a new screen session and run the skills
screen -L -d -m -S "\${screen_name}" bash
for skill_dir in *-skill; do
    echo -e "Booting \${skill_dir}"
    skill_name="\$(echo \${skill_dir} | cut -d '-' -f 2)"
    screen -S "\${screen_name}" -p 0 -X screen -t "\${skill_name}" bash -c "cd \${skill_dir} && \${boot_command}; bash"
done
EOF

echo "Writing boot-skill-forever script...."
cat <<EOF >"$scripts_dir/boot-skill-forever"
#!/usr/bin/env bash

if [ "\$#" -eq 1 ]; then
    cd \$1
fi
while true
do
   yarn boot
done
EOF

# Make the scripts executable
chmod +x "$scripts_dir/boot-all-skills-forever"
chmod +x "$scripts_dir/boot-skill-forever"

echo "Scripts written."

mkdir platform
cd platform

echo "Created platform directory"

DB_URL="$DB_CONNECTION_STRING"
[ "$DATABASE_NAME" == "default" ] && DB_NAME="mercury" || DB_NAME="$DATABASE_NAME"

echo "Installing Mercury..."

git clone https://github.com/sprucelabsai/spruce-mercury-api.git

cd "spruce-mercury-api" || exit

start_time=$(date +%s)
yarn
(yarn build.dev &)
end_time=$(date +%s)

if [[ -n "$MERCURY_ENV" && "$MERCURY_ENV" != "default" ]]; then
    echo "$MERCURY_ENV" >.env
else
    cat >.env <<EOF
SHEETS_REPORTER_ADAPTER="DummyAdapter"
DB_NAME=$DB_NAME
DB_CONNECTION_STRING=$DB_URL
MAXIMUM_LOG_PREFIXES_LENGTH=1
PORT=8081
ANONYMOUS_PERSON_PHONE=555-000-0000
DEMO_NUMBERS=*
ADMIN_NUMBERS=${PHONE_NUMBER}
DEFAULT_SENDER_DELIVERY_MECHANISM=passing
SHOULD_ENABLE_LLM=false
EOF
fi

cd ..

echo "Loading skills..."

readarray -t repos <../skills.txt

echo "Found ${#repos[@]} skills"

start_time=$(date +%s)

for repo in "${repos[@]}"; do

    if [[ "$repo" == */* ]]; then
        org_repo="$repo"
    else
        org_repo="sprucelabsai/$repo"
    fi

    skill=$(echo "${repo##*/}" | awk -F '-' '{ print $2 }')

    echo "Installing $skill..."

    git clone https://github.com/"$org_repo".git

    cd "${repo##*/}" || exit

    yarn
    (yarn build.dev &)

    echo "Done with rebuild"

    if [ -f "$SKILLS_ENV_CONFIG_PATH" ]; then
        echo "Loading skills env config ${SKILLS_ENV_CONFIG_PATH}"
        skill_config=$(jq -r ".$skill" $SKILLS_ENV_CONFIG_PATH)
        if [ -z "$skill_config" ]; then
            echo "Error: Skill config not found for $skill"
            exit 1
        fi
        echo "$skill_config" | jq -r 'to_entries[] | .key + "=\"" + .value + "\"" ' >>.env
        echo "Env generated from config"
    else
        if [ "$DATABASE_NAME" != "default" ]; then
            echo "DB_NAME=\"$DATABASE_NAME\"" >>.env
        else
            echo "DB_NAME=\"$skill\"" >>.env
        fi
        echo "DB_CONNECTION_STRING=\"$DB_CONNECTION_STRING\"" >>.env
    fi

    readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

    end_time=$(date +%s)

    echo "$readableSkill done: $((end_time - start_time)) seconds"

    cd ..

done

echo "Waiting for last skills to be installed..."

kill $NCP_PID || true
wait

if [ "$SHOULD_SERVE_HEARTWOOD" = "true" ]; then
    echo "Yay! We're almost done"
    echo "Next we need to build the Heartwood front-end!"

    cd "spruce-heartwood-skill" || exit

    yarn build.cdn

    write_script "serve-heartwood" "echo \"Heartwood Serving at http://localhost:8080\" && cd $(pwd)/dist && python3 -m http.server 8080"
else
    echo "Skipping serve-heartwood"
    write_script "serve-heartwood" "echo \"Heartwood serve skipped\""
fi

echo -e "Installation complete!"
