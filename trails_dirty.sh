#!/bin/bash
# set -x
set -e
set -o nounset
set -o pipefail

# cut a video into frames, fuse the pictures into a running average, and throw them back into a video.
# Goal: Elongate light trails

VIDEO_IN=$1

# Number of frames to be fused; length of trail
export TRAIL=$2

VIDEO_OUT=$(basename $VIDEO_IN .mp4)_${TRAIL}f_dirty.mp4

CURDIR=$PWD
TEMP=$(mktemp -d)
DARKEN_BLACK_FRAMES_PERCENTAGE=${3:-0}

# Split video into single frames
ffmpeg -i $VIDEO_IN ${TEMP}/out-%d.png
cd ${TEMP}
NUMBEROFFRAMES=$(ls out-*.png | wc -l)


echo 'Done.'

# STEPSIZE will be used to decrease the brightness. Since we're
# darkening the rolling window with each frame, STEPSIZE ^ TRAIL needs
# to be almost 0. Taking from the original script's idea of linearly
# darkening the frames, we demand STEPSIZE ^ TRAIL =
# (100/TRAIL). This python snippet calculates STEPSIZE, given TRAIL.
STEPSIZE=$(python - <<EOF
import os
frames = int(os.environ["TRAIL"])

print(int(100 *( 1.0 - (1.0/frames) ** (1.0/frames))))

EOF
)

FINAL_DARKENING=$((100-${STEPSIZE}))

# Initialize rolling-window.png to a black image - darkening that won't hurt.
convert  out-1.png -threshold 100% -alpha off rolling-window.png

# Iterate over all frames, cheating with the start number, so I don't have to add extra handling for the first few frames.
echo "Creating light trails for $NUMBEROFFRAMES frames:"
for FRAME in $(seq 1 ${NUMBEROFFRAMES})
do
	  echo -n "$FRAME "
    # Since we darken the entire window, the oldest frame has faded to
    # black (or something close enough, anyway) TRAIL frames later, so
    # don't worry about it.
    #
    # Backtick comments are a neat way to comment multi-line commands!
    convert -respect-parentheses \
            `# calculate light trail only frame` \
            \( out-${FRAME}.png -black-threshold 50% -brightness-contrast -${DARKEN_BLACK_FRAMES_PERCENTAGE}% -write mpr:BLACK \) \
            `# darken the window` \
            \( rolling-window.png -brightness-contrast -${STEPSIZE}% -write mpr:X \) \
            `# Add the rolling window (containing the "black-" versions of Frames FRAME-TAIL to FRAME-1)` \
            `# to the current frame` \
            \( out-${FRAME}.png mpr:X -compose Screen -composite -write fused-${FRAME}.png \) \
            `# add the next "black" frame to the rolling window` \
            \( mpr:BLACK mpr:X -compose Screen -composite -write rolling-window.png \) \
            null:
done
echo 'Done.'
# yuv420p pixel format to ensure the resulting clip plays back in non-ffmpeg players
ffmpeg -i fused-%d.png -pix_fmt yuv420p ${CURDIR}/${VIDEO_OUT}
cd ${CURDIR}
echo $TEMP
