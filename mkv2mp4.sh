#!/bin/bash
# mkv2mp4.sh
# Copyright (c) 2010 (c) BSD-type License, see License.txt
# by FighterHayabusa <fighterhayabusa@barbedwirebytecodebaconburger.com>
# Turns mkv into mp4 that plays on the PS3
# Usage: ./mkv2mp4.sh -f file.mkv

SLICE=2000M
L=2000
AUTOCONF=0
DEFAULTVA=0
CLEAN=1
while getopts "f:s:p:l:anhd" FLAG
do
	case "$FLAG" in
		l)
			L=$OPTARG
			;;
		s)
			SLICE=${OPTARG}M
			;;
    p)
      PRESETS=${OPTARG}
      AUTOCONF=0
      ;;
    n)
      CLEAN=0
      ;;
		f)
			MKVFILE=$OPTARG
			;;
		a)
			AUTOCONF=1
			;;
		h)
			echo ""
			echo "mkv2mp4.sh"
			echo "Copyright (c) 2010 BSD-type License, see License.txt"
			echo "by FighterHayabusa <fighterhayabusa@barbedwirebytecodebaconburger.com>"
			echo "Turns mkv into mp4 that plays on the PS3"
			echo "Usage: ./mkv2mp4.sh -l file_size_limit -s slice_size -f file.mkv"
			echo "Arguments:"
			echo "-l <size in MB>  Any mkv larger than <size in MB> will be split [default=2000]"
			echo "-s <size in MB>  If an mkv is split the pieces are <size in MB> each [default=2000]"
			echo "-f <filename.mkv>  The mkv-file to be transformed [MANDATORY]"
      echo "-p <video-track>:<audio-track>  Presets for video- and audio-track"
      echo "-d  Use default settings for video- and audio-track (0 and 1)"
      echo "-a  Attempt to auto-configure video- and audio-track (NOT YET IMPLEMENTED)"
			echo "-h  Shows this help-text"
			echo ""		
			exit 0
			;;
		d)
			DEFAULTVA=1
			;;
		*)
			echo "Unknown argument. Use -help for full list of arguments."
			exit 1
			;;
	esac
done

MP4FILE="${MKVFILE%.*}.mp4"

let LIMIT=(${L}*1024*1024)

echo "$MKVFILE $LIMIT $SLICE"

if [ ${AUTOCONF} -gt 0 ]; then
	# Attempt to automatically configure video and audio track
	echo "AUTOCONF not yet implemented."
	exit 1
else
	mkvmerge -i "$MKVFILE" 
	
  if [ ${#PRESETS} -gt 0 ]; then
    VTRACK=$(echo $PRESETS | sed -e 's/^\([0-9]*\)\:.*$/\1/g')
    ATRACK=$(echo $PRESETS | sed -e 's/^.*\:\([0-9]*\)$/\1/g')
	elif [ ${DEFAULTVA} -gt 0 ]; then
		VTRACK=0
		ATRACK=1
	else
		echo -n "Choose video-track [0]: " ; read VTRACK
		echo -n "Choose audio-track [1]: " ; read ATRACK
	fi

	# Check value of VTRACK and ATRACK and set defaults if necessary.
	if ! echo $VTRACK | grep -c "^[0-9][0-9]*$" > /dev/null ; then
		VTRACK=0;
	fi
	if ! echo $ATRACK | grep -c "^[0-9][0-9]*$" > /dev/null ; then
		ATRACK=1
	fi
fi

# Grab fps for video
TMPLIST=$MKVFILE.tmplist
mkvinfo $MKVFILE | grep -e '\(Track\ number:[[:space:]]\(.*\)$\|Track\ type:[[:space:]]\(.*\)$\|Codec ID:[[:space:]]\(.*\)$\|Default duration:[[:space:]]\(.*\)$\)' > $TMPLIST
VIDROW=`grep -n -e 'Track\ type:[[:space:]]video' $TMPLIST | sed -e 's/\([0-9][0-9]*\).*/\1/g'`
TOTROWS=`cat $TMPLIST | wc -l`
VFPS=`sed -n "${VIDROW},${TOTROWS}p" $TMPLIST | grep fps | grep video | sed -e 's/.*(\([[:digit:]]\+.*\) fps.*)/\1/' | sed -n '1,1p'`

# Set proper extension for audio output file
ACODEC=`mkvmerge -i "$MKVFILE" | grep audio | grep $ATRACK | sed -e 's/.*(.*\(DTS\|AC3\|AAC\))/\1/' | tr "[:upper:]" "[:lower:]"`
if ! echo $ACODEC | grep -c "^ac3\|dts\|aac$" > /dev/null ; then
	AEXT=other
else
	AEXT=$ACODEC
fi

# Split large files into $SLICE (MB) size pieces if size exceeds $LIMIT in bytes
# (added because I had some trouble with mkv-files bigger than 2G)
SPLT="${MKVFILE}.split-tmp"
FILESIZE=`stat -c %s "$MKVFILE"`
if [ $FILESIZE -gt $LIMIT ]; then
	echo "Splitting the file..."
	mkvmerge -o $SPLT.mkv --split $SLICE "$MKVFILE" > /dev/null 2>&1
	MKVS=`ls $SPLT*.mkv`
	echo "Done."
else
	MKVS="$MKVFILE"
fi

COUNT=0
for MKV in $MKVS
do
	let COUNT=$COUNT+1
		
	# Extract tracks
	echo "Extracting tracks..."
	mkvextract tracks $MKV $VTRACK:$MKVFILE.tmpvid.h264 $ATRACK:$MKVFILE.tmpaud.$AEXT
	echo "Done."
	
	# Encode audio
	echo "Encoding audio to AAC..."
	if [ "$AEXT" == "ac3" ]; then
		# If audio is AC3
		a52dec -o wav -g 6 $MKVFILE.tmpaud.$AEXT | neroAacEnc -ignorelength -q 0.20 -if - -of $MKVFILE.tmpaud.aac
	elif [ "$AEXT" == "xxxdts" ]; then
		# If audio is DTS
		AUDIODUMP=$MKVFILE.audiodump.wav
		mkfifo $AUDIODUMP
		neroAacEnc -ignorelength -q 0.30 -if $AUDIODUMP -of tmpaud.aac & mplayer "$MKV" -ac ffdca -channels 6 -af format=s16le,channels=6:6:0:2:1:0:2:1:3:4:4:5:5:3 -vo null -vc null -ao pcm:fast:waveheader:file=$AUDIODUMP -novideo -quiet -nolirc
		rm $AUDIODUMP
	elif [ "$AEXT" == "aac" ]; then
		# if audio is AAC
		# Do nothing
		sleep 0
	else
		ffmpeg -i "$MKV" -vn -acodec aac -ac 2 -ar 48000 -ab 192k -strict experimental $MKVFILE.tmpaud.aac
	fi
	echo "Done."

	# Put it all back together again
	echo "Wrapping up video and audio in mp4-container..."
	NUMBER=$(printf %03d $COUNT)
	FILENAME="${MP4FILE%.*}-$NUMBER.mp4"
	MP4Box -add $MKVFILE.tmpvid.h264:fps=$VFPS -add $MKVFILE.tmpaud.aac "$FILENAME"
	echo "Done."
done

if [ $COUNT -eq 1 ]; then
	mv "$FILENAME" "$MP4FILE"
fi

if [ $CLEAN -eq 1 ]; then
  echo "Cleaning up..."
  rm -rf $TMPLIST > /dev/null 2>&1
  rm -rf $MKVFILE.tmpaud.* > /dev/null 2>&1
  rm -rf $MKVFILE.tmpvid.* > /dev/null 2>&1
  if [ "$SPLT" != "" ]; then
    rm -rf $SPLT*.mkv > /dev/null 2>&1
  fi
fi
echo "Done."


