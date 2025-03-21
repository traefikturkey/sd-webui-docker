#!/usr/bin/env bash
set -Eeuo pipefail

# Set up our directory mapping table
repo_root=${ROOT_DIR:-'/stable-diffusion-webui'}
data_dir=${DATA_DIR:-'/data'}
models_dir=${MODELS_DIR:-'/models'}  # Change this line to use the MODELS_DIR variable instead of DATA_DIR
declare -A path_map

path_map["${repo_root}/models/Stable-diffusion"]="${models_dir}/StableDiffusion"
path_map["${repo_root}/models/VAE"]="${models_dir}/VAE"
path_map["${repo_root}/models/Codeformer"]="${models_dir}/Codeformer"
path_map["${repo_root}/models/ControlNet"]="${models_dir}/ControlNet"
path_map["${repo_root}/models/GFPGAN"]="${models_dir}/GFPGAN"
path_map["${repo_root}/models/ESRGAN"]="${models_dir}/ESRGAN"
path_map["${repo_root}/models/BSRGAN"]="${models_dir}/BSRGAN"
path_map["${repo_root}/models/RealESRGAN"]="${models_dir}/RealESRGAN"
path_map["${repo_root}/models/SwinIR"]="${models_dir}/SwinIR"
path_map["${repo_root}/models/ScuNET"]="${models_dir}/ScuNET"
path_map["${repo_root}/models/LDSR"]="${models_dir}/LDSR"  
path_map["${repo_root}/models/hypernetworks"]="${models_dir}/Hypernetworks"
path_map["${repo_root}/models/torch_deepdanbooru"]="${models_dir}/Deepdanbooru"
path_map["${repo_root}/models/BLIP"]="${models_dir}/BLIP"
path_map["${repo_root}/models/midas"]="${models_dir}/MiDaS"
path_map["${repo_root}/models/Lora"]="${models_dir}/Lora"
path_map["${repo_root}/models/LyCORIS"]="${models_dir}/Lora"
path_map["${repo_root}/models/openpose"]="${models_dir}/openpose"
path_map["${repo_root}/models/Unet-onnx"]="${models_dir}/Unet-onnx"
path_map["${repo_root}/models/Unet-trt"]="${models_dir}/Unet-trt"

# extra hack for CodeFormer
path_map["${repo_root}/repositories/CodeFormer/weights/facelib"]="${models_dir}/.cache"

# add pip cache path to path_map
if [[ -d ${HOME} ]]; then
    echo "Using ${HOME}/.cache for pip cache"
    path_map["${HOME}/.cache"]="${data_dir}/.cache"
else
    echo "Warning: No home directory found, using /tmp/.cache for pip cache"
    path_map["/tmp/.cache"]="${data_dir}/.cache"
fi

# add other paths to path_map
path_map["${repo_root}/embeddings"]="${data_dir}/embeddings"

if [[ "${SD_WEBUI_VARIANT}" == "vlad" ]]; then
    echo "Running vladmandic webui variant"
    config_dir="${data_dir}/config/vlad"
    if [[ ! -d ${config_dir} ]]; then
        echo "vlad config folder not found, creating..."
        mkdir -p "${config_dir}"
        if [[ -d "${data_dir}/config/auto" ]]; then
            echo "Found existing AUTOMATIC1111 config, copying to vlad config"
            cp -au "${data_dir}/config/auto" "${data_dir}/config/vlad"
            echo "Purging extensions from vlad config (most are built-in and copying breaks them)"
            rm -fr "${data_dir}/config/vlad/extensions"
        fi
        echo "Configuration ready."
    fi
else
    echo "Running AUTOMATIC1111 webui variant"
    config_dir="${data_dir}/config/auto"
fi

path_map["${repo_root}/extensions"]="${config_dir}/extensions"
path_map["${repo_root}/.vscode"]="${config_dir}/.vscode"
# scripts we can't symlink because of gradio security reasons
#path_map["${repo_root}/scripts"]="${config_dir}/auto/scripts"

### Execution begins here ###

# create path maps and symlink them
for tgt_path in "${!path_map[@]}"; do
    echo -n "link ${tgt_path#"/${repo_root}"}"
    # get source path and create it if it doesn't exist
    src_path="${path_map[${tgt_path}]}"
    [[ -d ${src_path} ]] || mkdir -vp "${src_path}" 2>&1 > /dev/null

    # ensure target parent directory exists
    tgt_parent="$(dirname "${tgt_path}")"
    [[ -d ${tgt_parent} ]] || mkdir -vp "${tgt_parent}" 2>&1 > /dev/null

    # clean out target directory and symlink it to source path
    rm -rf "${tgt_path}"
    ln -sT "${src_path}" "${tgt_path}"
    echo " -> ${src_path} (directory)"
done

# Map config and script files to their target locations
declare -A file_map
# add files to file_map
file_map["${repo_root}/config.json"]="${config_dir}/config.json"
file_map["${repo_root}/ui-config.json"]="${config_dir}/ui-config.json"
file_map["${repo_root}/user.css"]="${config_dir}/user.css"

# copy default config.json if there isn't one
if [ ! -f "${config_dir}/config.json" ]; then
    cp -n "/docker/config.json" "${config_dir}/config.json"
fi
# create empty ui-config.json if none provided
if [ ! -f "${config_dir}/ui-config.json" ]; then
    echo '{}' > "${config_dir}/ui-config.json"
fi
# create empty user.css if none provided
if [ ! -f "${config_dir}/user.css" ]; then
    echo '' > "${config_dir}/user.css"
fi

# merge system config.json with default config.json
jq '. * input' "${config_dir}/config.json" "/docker/config.json" \
    | sponge "${config_dir}/config.json"

# symlink files
for tgt_path in "${!file_map[@]}"; do
    echo -n "link ${tgt_path#"/${repo_root}"}"

    # get source path
    src_path="${file_map[${tgt_path}]}"

    # ensure target parent directory exists
    tgt_parent="$(dirname "${tgt_path}")"
    [[ -d ${tgt_parent} ]] || mkdir -vp "${tgt_parent}" 2>&1 > /dev/null

    # delete target if it exists and symlink it to source path
    rm -rf "${tgt_path}"
    ln -sT "${src_path}" "${tgt_path}"
    echo " -> ${src_path} (file)"
done

# Copy scripts individually to avoid purging the directory
echo 'Copying scripts (if present): '
cp -vrfTs "${config_dir}"/scripts/*.py "${repo_root}/scripts/" || true

# Set git config so it won't warn and confuse the webui
git config --system pull.rebase true
git config --system rebase.autostash true

# Run startup script if it exists
if [ -f "${config_dir}/startup.sh" ]; then
    pushd "${repo_root}" > /dev/null
    echo "Running startup script..."
    # shellcheck source=/dev/null
    . "${config_dir}/startup.sh"
    popd > /dev/null
fi

exec "$@"
