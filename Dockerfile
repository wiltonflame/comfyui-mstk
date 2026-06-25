FROM hearmeman/comfyui-wan-template:v22

# Renomeia o start original antes de substituir
RUN mv /start.sh /start_original.sh

COPY start_wilton.sh /start.sh
RUN chmod +x /start.sh
