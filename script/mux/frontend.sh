#!/bin/sh

case ":$LD_LIBRARY_PATH:" in
	*":/opt/muos/extra/lib:"*) ;;
	*) export LD_LIBRARY_PATH="/opt/muos/extra/lib:$LD_LIBRARY_PATH" ;;
esac

. /opt/muos/script/var/func.sh

DEVICE_BOARD="$(GET_VAR "device" "board/name")"

ACT_GO=/tmp/act_go
APP_GO=/tmp/app_go
ASS_GO=/tmp/ass_go
GOV_GO=/tmp/gov_go
GVR_GO=/tmp/gvr_go
IDX_GO=/tmp/idx_go
PIK_GO=/tmp/pik_go
ROM_GO=/tmp/rom_go
RES_GO=/tmp/res_go

EX_CARD=/tmp/explore_card
EX_NAME=/tmp/explore_name
EX_DIR=/tmp/explore_dir

CL_DIR=/tmp/collection_dir
CL_AMW=/tmp/add_mode_work

MUX_AUTH=/tmp/mux_auth
MUX_LAUNCHER_AUTH=/tmp/mux_launcher_auth

DEF_ACT=$(GET_VAR "global" "settings/general/startup")
printf '%s\n' "$DEF_ACT" >$ACT_GO

echo "root" >$EX_CARD

LAST_PLAY=$(cat "/opt/muos/config/lastplay.txt")
LAST_INDEX=0

LOG_INFO "$0" 0 "FRONTEND" "Setting default CPU governor"
DEF_GOV=$(GET_VAR "device" "cpu/default")
printf '%s' "$DEF_GOV" >"$(GET_VAR "device" "cpu/governor")"
if [ "$DEF_GOV" = ondemand ]; then
	GET_VAR "device" "cpu/sampling_rate_default" >"$(GET_VAR "device" "cpu/sampling_rate")"
	GET_VAR "device" "cpu/up_threshold_default" >"$(GET_VAR "device" "cpu/up_threshold")"
	GET_VAR "device" "cpu/sampling_down_factor_default" >"$(GET_VAR "device" "cpu/sampling_down_factor")"
	GET_VAR "device" "cpu/io_is_busy_default" >"$(GET_VAR "device" "cpu/io_is_busy")"
fi

LOG_INFO "$0" 0 "FRONTEND" "Checking for last or resume startup"
if [ "$(GET_VAR "global" "settings/general/startup")" = "last" ] || [ "$(GET_VAR "global" "settings/general/startup")" = "resume" ]; then
	GO_LAST_BOOT=1

	if [ -n "$LAST_PLAY" ]; then
		LOG_INFO "$0" 0 "FRONTEND" "Checking for network and retrowait"

		if [ "$(GET_VAR "global" "settings/advanced/retrowait")" -eq 1 ]; then
			NET_START="/tmp/net_start"
			OIP=0

			while :; do
				NW_MSG=$(printf "Waiting for network to connect... (%s)\n\nPress START to continue loading\nPress SELECT to go to main menu" "$OIP")
				/opt/muos/extra/muxstart 0 "$NW_MSG"
				OIP=$((OIP + 1))

				if [ "$(cat "$(GET_VAR "device" "network/state")")" = "up" ]; then
					LOG_SUCCESS "$0" 0 "FRONTEND" "Network connected"
					/opt/muos/extra/muxstart 0 "Network connected"

					PIP=0
					while ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; do
						PIP=$((PIP + 1))
						LOG_INFO "$0" 0 "FRONTEND" "Verifying connectivity..."
						/opt/muos/extra/muxstart 0 "Verifying connectivity... (%s)" "$PIP"
						/opt/muos/bin/toybox sleep 1
					done

					LOG_SUCCESS "$0" 0 "FRONTEND" "Connectivity verified! Booting content!"
					/opt/muos/extra/muxstart 0 "Connectivity verified! Booting content!"

					GO_LAST_BOOT=1
					break
				fi

				if [ "$(cat "$NET_START")" = "ignore" ]; then
					LOG_SUCCESS "$0" 0 "FRONTEND" "Ignoring network connection"
					/opt/muos/extra/muxstart 0 "Ignoring network connection... Booting content!"

					GO_LAST_BOOT=1
					break
				fi

				if [ "$(cat "$NET_START")" = "menu" ]; then
					LOG_SUCCESS "$0" 0 "FRONTEND" "Booting to main menu"
					/opt/muos/extra/muxstart 0 "Booting to main menu!"

					GO_LAST_BOOT=0
					break
				fi

				/opt/muos/bin/toybox sleep 1
			done
		fi

		if [ $GO_LAST_BOOT -eq 1 ]; then
			LOG_INFO "$0" 0 "FRONTEND" "Booting to last launched content"
			cat "$LAST_PLAY" >"$ROM_GO"

			CONTENT_GOV="$(basename "$LAST_PLAY" .cfg).gov"
			if [ -e "$CONTENT_GOV" ]; then
				printf "%s" "$(cat "$CONTENT_GOV")" >$GVR_GO
			else
				CONTENT_GOV="$(dirname "$LAST_PLAY")/core.gov"
				if [ -e "$CONTENT_GOV" ]; then
					printf "%s" "$(cat "$CONTENT_GOV")" >$GVR_GO
				else
					LOG_INFO "$0" 0 "FRONTEND" "No governor found for launched content"
				fi
			fi

			/opt/muos/script/mux/launch.sh last
		fi
	fi

	echo launcher >$ACT_GO
fi

LOG_INFO "$0" 0 "FRONTEND" "Starting frontend launcher"

cp /opt/muos/log/*.log "$(GET_VAR "device" "storage/rom/mount")/MUOS/log/boot/." &

PROCESS_CONTENT_ACTION() {
	ACTION="$1"
	MODULE="$2"

	[ ! -s "$ACTION" ] && return

	{
		IFS= read -r ROM_NAME
		IFS= read -r ROM_DIR
		IFS= read -r ROM_SYS
		IFS= read -r FORCED_FLAG
	} <"$ACTION"

	rm "$ACTION"
	echo "$MODULE" >"$ACT_GO"

	[ "$FORCED_FLAG" -eq 1 ] && echo "option" >"$ACT_GO"
}

LAST_INDEX_CHECK() {
	LAST_INDEX=0
	if [ -s "$IDX_GO" ] && [ ! -s "$CL_AMW" ]; then
		read -r LAST_INDEX <"$IDX_GO"
		LAST_INDEX=${LAST_INDEX:-0}
		rm -f "$IDX_GO"
	fi
}

while :; do
	CHECK_BGM ignore &
	pkill -9 -f "gptokeyb" &

	# Reset DPAD<>ANALOGUE switch for H700 devices
	[ "$DEVICE_BOARD" = "rg*" ] && echo 0 >"/sys/class/power_supply/axp2202-battery/nds_pwrkey"

	# Process content association and governor actions
	PROCESS_CONTENT_ACTION "$ASS_GO" "assign"
	PROCESS_CONTENT_ACTION "$GOV_GO" "governor"

	# Content Loader
	[ -s "$ROM_GO" ] && /opt/muos/script/mux/launch.sh

	[ -s "$ACT_GO" ] && {
		IFS= read -r ACTION <"$ACT_GO"

		case "$ACTION" in
			"launcher")
				touch /tmp/pdi_go
				[ -s "$MUX_AUTH" ] && rm "$MUX_AUTH"
				[ -s "$MUX_LAUNCHER_AUTH" ] && rm "$MUX_LAUNCHER_AUTH"
				EXEC_MUX "launcher" "muxlaunch"
				;;

			"option") EXEC_MUX "explore" "muxoption" -c "$ROM_NAME" -d "$ROM_DIR" -s "$ROM_SYS" ;;
			"assign") EXEC_MUX "option" "muxassign" -a 0 -c "$ROM_NAME" -d "$ROM_DIR" -s "$ROM_SYS" ;;
			"governor") EXEC_MUX "option" "muxgov" -a 0 -c "$ROM_NAME" -d "$ROM_DIR" -s "$ROM_SYS" ;;
			"search")
				[ -s "$EX_DIR" ] && IFS= read -r EX_DIR_CONTENT <"$EX_DIR"
				EXEC_MUX "option" "muxsearch" -d "$EX_DIR_CONTENT"
				if [ -s "$RES_GO" ]; then
					IFS= read -r RES_CONTENT <"$RES_GO"
					printf "%s" "${RES_CONTENT##*/}" >"$EX_NAME"
					printf "%s" "${RES_CONTENT%/*}" >"$EX_DIR"
					printf "%s" "$(echo "$RES_CONTENT" | sed 's|.*/\([^/]*\)/ROMS.*|\1|')" >"$EX_CARD"
					EXEC_MUX "option" "muxplore" -i 0 -d "$(cat "$EX_DIR")"
				fi
				;;

			"app")
				AUTHORIZED=0
				if [ "$(GET_VAR "global" "settings/advanced/lock")" -eq 1 ] && [ ! -e "$MUX_LAUNCHER_AUTH" ]; then
					EXEC_MUX "launcher" "muxpass" -t launch
					if [ "$EXIT_STATUS" -eq 1 ]; then
						AUTHORIZED=1
						touch "$MUX_LAUNCHER_AUTH"
					fi
				else
					AUTHORIZED=1
				fi
				if [ "$AUTHORIZED" -eq 1 ]; then
					EXEC_MUX "launcher" "muxapp"
					if [ -s "$APP_GO" ]; then
						IFS= read -r RUN_APP <"$APP_GO"
						rm "$APP_GO"
						case "$RUN_APP" in
							*"Archive Manager"*)
								echo archive >$ACT_GO
								;;
							*"Task Toolkit"*)
								echo task >$ACT_GO
								;;
							*)
								STOP_BGM
								"$(GET_VAR "device" "storage/rom/mount")/MUOS/application/${RUN_APP}/mux_launch.sh"
								;;
						esac
					fi
				fi
				;;

			"config")
				if [ "$(GET_VAR "global" "settings/advanced/lock")" -eq 1 ] && [ ! -e "$MUX_AUTH" ] && [ ! "$PREVIOUS_MODULE" = "muxtweakgen" ]; then
					EXEC_MUX "launcher" "muxpass" -t setting
					if [ "$EXIT_STATUS" -eq 1 ]; then
						EXEC_MUX "launcher" "muxconfig"
						touch "$MUX_AUTH"
					fi
				else
					EXEC_MUX "launcher" "muxconfig"
				fi
				;;

			"picker")
				[ -s "$PIK_GO" ] && IFS= read -r PIK_CONTENT <"$PIK_GO"
				EXPLORE_DIR=""
				[ -s "$EX_DIR" ] && IFS= read -r EXPLORE_DIR <"$EX_DIR"
				EXEC_MUX "custom" "muxpicker" -m "$PIK_CONTENT" -d "$EXPLORE_DIR"
				;;

			"explore")
				LAST_INDEX_CHECK
				EXPLORE_DIR=""
				[ -s "$EX_DIR" ] && IFS= read -r EXPLORE_DIR <"$EX_DIR"
				EXEC_MUX "launcher" "muxassign" -a 1 -c "$ROM_NAME" -d "$EXPLORE_DIR" -s none
				EXEC_MUX "launcher" "muxgov" -a 1 -c "$ROM_NAME" -d "$EXPLORE_DIR" -s none
				EXEC_MUX "launcher" "muxplore" -d "$EXPLORE_DIR" -i "$LAST_INDEX"
				;;

			"collection")
				LAST_INDEX_CHECK
				ADD_MODE=0
				if [ -s "$CL_AMW" ]; then
					ADD_MODE=1
					LAST_INDEX=0
				fi
				COLLECTION_DIR=""
				[ -s "$CL_DIR" ] && IFS= read -r COLLECTION_DIR <"$CL_DIR"
				find "/run/muos/storage/info/collection" -maxdepth 2 -type f -size 0 -delete
				EXEC_MUX "launcher" "muxcollect" -a "$ADD_MODE" -d "$COLLECTION_DIR" -i "$LAST_INDEX"
				;;

			"history")
				LAST_INDEX_CHECK
				find "/run/muos/storage/info/history" -maxdepth 1 -type f -size 0 -delete
				EXEC_MUX "launcher" "muxhistory" -i "$LAST_INDEX"
				;;

			"credits")
				STOP_BGM
				/opt/muos/bin/nosefart /opt/muos/share/media/support.nsf &
				EXEC_MUX "info" "muxcredits"
				pkill -9 -f "nosefart" &
				START_BGM
				;;

			"tweakadv")
				EXEC_MUX "tweakgen" "muxtweakadv"
				if [ "$(GET_VAR "global" "settings/advanced/lock")" -eq 0 ]; then
					[ -f "$MUX_AUTH" ] && rm "$MUX_AUTH"
					[ -f "$MUX_LAUNCHER_AUTH" ] && rm "$MUX_LAUNCHER_AUTH"
				fi
				;;

			"info") EXEC_MUX "launcher" "muxinfo" ;;
			"archive") EXEC_MUX "app" "muxarchive" ;;
			"task") EXEC_MUX "app" "muxtask" ;;
			"tweakgen") EXEC_MUX "config" "muxtweakgen" ;;
			"connect") EXEC_MUX "config" "muxconnect" ;;
			"custom") EXEC_MUX "config" "muxcustom" ;;
			"network") EXEC_MUX "connect" "muxnetwork" ;;
			"language") EXEC_MUX "config" "muxlanguage" ;;
			"webserv") EXEC_MUX "connect" "muxwebserv" ;;
			"hdmi") EXEC_MUX "tweakgen" "muxhdmi" ;;
			"rtc") EXEC_MUX "tweakgen" "muxrtc" ;;
			"storage") EXEC_MUX "config" "muxstorage" ;;
			"power") EXEC_MUX "config" "muxpower" ;;
			"visual") EXEC_MUX "config" "muxvisual" ;;
			"net_profile") EXEC_MUX "network" "muxnetprofile" ;;
			"net_scan") EXEC_MUX "network" "muxnetscan" ;;
			"timezone") EXEC_MUX "rtc" "muxtimezone" ;;
			"screenshot") EXEC_MUX "info" "muxshot" ;;
			"space") EXEC_MUX "info" "muxspace" ;;
			"tester") EXEC_MUX "info" "muxtester" ;;
			"system") EXEC_MUX "info" "muxsysinfo" ;;

			"reboot") /opt/muos/script/mux/quit.sh reboot frontend ;;
			"shutdown") /opt/muos/script/mux/quit.sh poweroff frontend ;;

			*) printf "Unknown Module: %s\n" "$ACTION" >&2 ;;
		esac
	}

done
