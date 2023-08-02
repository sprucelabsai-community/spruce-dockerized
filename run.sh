

# Define a function to write an alias
write_alias() {
    local alias_name=$1
    local alias_command=$2
    local shellrc="$HOME/.bashrc"
    if [[ $SHELL == *"zsh"* ]]; then
        shellrc="$HOME/.zshrc"
    elif [[ $SHELL == *"fish"* ]]; then
        shellrc="$HOME/.config/fish/config.fish"
    elif [[ $SHELL == *"csh"* ]]; then
        shellrc="$HOME/.cshrc"
    fi
    echo "alias $alias_name='$alias_command'" >>"$shellrc"
    echo -e "Done!\n\nRun '$alias_name' in another terminal!"
}

scripts_dir="$HOME/.sprucebot"

# Create scripts directory
mkdir -p "$scripts_dir"

# Write the scripts
echo "Writing boot-all-skills-forever script to $scripts_dir/boot-all-skills-forever..."
cat <<EOF >"$scripts_dir/boot-all-skills-forever"
#!/usr/bin/env bash

screen_name="skills"
boot_command="bash $scripts_dir/boot-skill-forever"
echo "starting boot all skills forever"
# Quit any existing screens with the same name
screen -S "\${screen_name}" -X quit

# Create a new screen session and run the skills
screen -L -d -m -S "\${screen_name}" bash
for skill_dir in *-skill; do
    echo "booting \${skill_dir}"
    skill_name="\$(echo \${skill_dir} | cut -d '-' -f 2)"
    screen -S "\${screen_name}" -p 0 -X screen -t "\${skill_name}" bash -c "cd \${skill_dir} && \${boot_command}; bash"
done
EOF

echo "Writing boot-skill-forever script to $scripts_dir/boot-skill-forever..."
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

write_alias "boot-skill-forever" "bash $scripts_dir/boot-skill-forever"
write_alias "boot-all-skills-forever" "bash $scripts_dir/boot-all-skills-forever"


#boot up mercury
cd "spruce-mercury-api"
yarn boot & 
cd ..

repos=("spruce-heartwood-skill" "spruce-organization-skill" "spruce-locations-skill" "spruce-calendar-skill" "spruce-jokes-skill" "spruce-people-skill" "spruce-files-skill" "spruce-images-skill" "spruce-reminders-skill" "spruce-feed-skill" "spruce-appointments-skill" "spruce-shifts-skill" "spruce-roles-skill")

ls
for repo in "${repos[@]}"; do
    (
        skill="$(echo ${repo} | cut -d '-' -f 2)"
        echo "trying to boot $skill"
        cd "$repo" || exit
        readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

        spruce set.remote --remote=local && spruce login --phone "$PHONE_NUMBER" --pin 0000 && spruce register --nameReadable "$readableSkill" --nameKebab "$skill"

        echo "$readableSkill Installed: $((end_time - start_time)) seconds"
        cd ..
    )
done


echo "Updating isPublished and canBeInstalled for skills"


# array of lowercase skill namespaces
namespaces=("appointments" "developer" "esm" "feedback" "forms" "groups" "invite" "lbb" "profile" "reminders" "shifts" "skills" "theme" "waivers" )


# loop through all directories in the current directory that end in -skill
for dir in *-skill; do
  if [[ -d $dir ]]; then
    # change into the directory
    cd "$dir"
    # get the namespace from package.json
    namespace=$(grep '"namespace"' package.json | awk -F: '{print $2}' | tr -d '," ')
    # check if namespace is in the namespaces array
    if [[ " ${namespaces[*]} " == *"$namespace"* ]]; then
      # set isPublished and canBeInstalled to true
      mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: true}})"
    else
      # set isPublished and canBeInstalled to false
      mongosh mercury --eval "db.skills.updateMany({slug: '$namespace'}, { \$set: {isPublished: true, canBeInstalled: false}})"
    fi
    # change back to the parent directory
    cd ..
  fi
done

bash $scripts_dir/boot-all-skills-forever

cd "spruce-heartwood-skill" || exit
yarn build.cdn # >>/dev/null 2>&1
cd ..

bash -c "cd spruce-heartwood-skill/dist && python3 -m http.server 8080"
