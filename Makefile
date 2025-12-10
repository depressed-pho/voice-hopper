ROOT		= ${HOME}/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion
UTIL_DIR	= ${ROOT}/Scripts/Utility
MOD_DIR		= ${ROOT}/Modules/Lua/VoiceHopper

all:
	echo "Run 'make install' or 'make uninstall'"

install:
	mkdir -p "${UTIL_DIR}"
	ln -f "Scripts/Utility/Voice Hopper.lua" "${UTIL_DIR}/"

	mkdir -p "${MOD_DIR}"
	ln -f "Modules/Lua/VoiceHopper/class.lua" "${MOD_DIR}/"
	ln -f "Modules/Lua/VoiceHopper/lazy.lua" "${MOD_DIR}/"
	ln -f "Modules/Lua/VoiceHopper/symbol.lua" "${MOD_DIR}/"

uninstall:
	rm -f "${UTIL_DIR}/Voice Hopper.lua"
	rm -rf "${MOD_DIR}"
