ROOT = ${HOME}/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion

all:
	echo "Run 'make install' or 'make uninstall'"

install:
	ln -f "Scripts/Utility/Voice Hopper.lua" "${ROOT}/Scripts/Utility/"

uninstall:
	rm -f "${ROOT}/Scripts/Utility/Voice Hopper.lua"
