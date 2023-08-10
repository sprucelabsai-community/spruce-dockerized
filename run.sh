echo -e "Setting up spruce skills...this might take a minute...\n"

WILL_BOOT_ACTION=${WILL_BOOT_ACTION:-register}
SHOULD_UPDATE_PUBLISHED_STATUS=${SHOULD_UPDATE_PUBLISHED_STATUS:-true}

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

for skill_dir in *-skill; do
    (
        skill=$(echo "${skill_dir}" | cut -d '-' -f 2)

        echo -e "Registering $skill..."
        cd "$skill_dir" || exit

        readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

        spruce set.remote --remote=local >>/dev/null 2>&1 && spruce login --phone "$PHONE_NUMBER" --pin 0000 >>/dev/null 2>&1

        if [ "$WILL_BOOT_ACTION" = "register" ]; then
            spruce register --nameReadable "$readableSkill" --nameKebab "$skill"
        fi

        if [ "$WILL_BOOT_ACTION" = "login" ]; then
            spruce login.skill --skillSlug "$skill"
        fi

        echo -e "$readableSkill Installed: $((end_time - start_time)) seconds\n"
        cd ..
    ) &
done

if [ "$SHOULD_UPDATE_PUBLISHED_STATUS" = true ]; then

    echo -e "Configuring skills...\n "

    namespaces=("appointments" "developer" "esm" "feedback" "forms" "groups" "invite" "lbb" "profile" "reminders" "shifts" "skills" "theme" "waivers")

    for dir in *-skill; do
        if [[ -d $dir ]]; then
            cd "$dir"
            namespace=$(grep '"namespace"' package.json | awk -F: '{print $2}' | tr -d '," ') >>/dev/null 2>&1
            if [[ " ${namespaces[*]} " == *"$namespace"* ]]; then
                mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: true}})" >>/dev/null 2>&1
            else
                mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: false}})" >>/dev/null 2>&1
            fi
            cd ..
        fi
    done

fi

scripts_dir="$HOME/.sprucebot"
bash $scripts_dir/boot-all-skills-forever

if [ -d "spruce-heartwood-skill/dist" ]; then
    cd spruce-heartwood-skill/dist
    python3 -m http.server 8080
fi
