echo -e "Setting up spruce skills...this might take a minute...\n"

WILL_BOOT_ACTION=${WILL_BOOT_ACTION:-register}
SHOULD_UPDATE_PUBLISHED_STATUS=${SHOULD_UPDATE_PUBLISHED_STATUS:-true}
SKILLS_ENV_CONFIG_PATH=false

for arg in "$@"; do
    case $arg in
    --willBootAction=*)
        WILL_BOOT_ACTION="${arg#*=}"
        shift
        ;;
    --shouldUpdatePublishedStatus=*)
        SHOULD_UPDATE_PUBLISHED_STATUS="${arg#*=}"
        shift
        ;;
    --skillsEnvConfigPath=*)
        SKILLS_ENV_CONFIG_PATH="${arg#*=}"
        shift
        ;;
    *)
        shift
        ;;
    esac
done

cd platform
echo "Booting Mercury"
cd "spruce-mercury-api"
yarn boot &
cd ..

clear
echo "Booting Mercury..."
sleep 10
clear

skill_count=0

for skill_dir in *-skill; do

    skill=$(echo "${skill_dir}" | cut -d '-' -f 2)

    echo -e "Registering $skill..."
    cd "$skill_dir" || exit

    readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

    if [ "$SKILLS_ENV_CONFIG_PATH" != "false" ]; then
        skill_config=$(jq -r ".$skill" $SKILLS_ENV_CONFIG_PATH)
        echo "$skill_config" | jq -r 'to_entries[] | .key + "=\"" + .value + "\"" ' >>.env
    fi

    spruce set.remote --remote=local >/dev/null

    if [ "$skill_count" -eq 0 ]; then
        spruce login --phone "$PHONE_NUMBER" --pin 0000 >/dev/null
    fi

    if [ "$WILL_BOOT_ACTION" = "register" ]; then
        (spruce register --nameReadable "$readableSkill" --nameKebab "$skill" >/dev/null) &
    fi

    if [ "$WILL_BOOT_ACTION" = "login" ]; then
        (spruce login.skill --skillSlug "$skill" >/dev/null) &
    fi

    if [ "$WILL_BOOT_ACTION" = "build" ]; then
        (yarn build.dev >/dev/null) &
    fi

    echo -e "$readableSkill Ready: $((end_time - start_time)) seconds\n"
    cd ..

    skill_count=$((skill_count + 1))
done

if [ "$SHOULD_UPDATE_PUBLISHED_STATUS" = true ]; then

    echo -e "Configuring skills...\n "

    namespaces=("appointments" "developer" "esm" "feedback" "forms" "groups" "invite" "lbb" "profile" "reminders" "shifts" "skills" "theme" "waivers")

    for dir in *-skill; do
        if [[ -d $dir ]]; then
            cd "$dir"
            namespace=$(grep '"namespace"' package.json | awk -F: '{print $2}' | tr -d '," ') >/dev/null
            if [[ " ${namespaces[*]} " == *"$namespace"* ]]; then
                mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: true}})" >/dev/null
            else
                mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: false}})" >/dev/null
            fi
            cd ..
        fi
    done

fi

scripts_dir="$HOME/.sprucebot"
bash $scripts_dir/boot-all-skills-forever &
bash $scripts_dir/serve-heartwood &

tail -f /dev/null
