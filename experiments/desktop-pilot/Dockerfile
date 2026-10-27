FROM ai-docker-pilot-base:local
COPY setup_ssh.sh /usr/local/bin/setup_desktop_pilot.sh
COPY entrypoint.sh /usr/local/bin/desktop_pilot_entrypoint.sh
RUN chmod +x /usr/local/bin/setup_desktop_pilot.sh /usr/local/bin/desktop_pilot_entrypoint.sh
ENTRYPOINT ["/usr/local/bin/desktop_pilot_entrypoint.sh"]
