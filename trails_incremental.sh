#!/bin/bash
#set -x
set -e
set -o nounset
set -o pipefail

# cut a video into frames, fuse the pictures into a running average, and throw them back into a video.
# Goal: Elongate light trails

VIDEO_IN=$1

# Number of frames to be fused; length of trail
export TRAIL=$2

VIDEO_OUT=$(basename $VIDEO_IN .mp4)_${TRAIL}f_rolling.mp4

CURDIR=$PWD
TEMP=$(mktemp -d)

# Split video into single frames
ffmpeg -i $VIDEO_IN ${TEMP}/out-%d.png
cd ${TEMP}
NUMBEROFFRAMES=$(ls out-*.png | wc -l)
# Convert all frames into near blackness. Choose the threshold value to black out everything but the light trail.
# out-n.png -> black-n.png
echo 'Converting to "light trail only" pictures...'
for i in out-*.png; do convert -black-threshold 50% $i $(echo $i | sed 's/out/black/'); done
echo 'Done.'

# STEPSIZE will be used to decrease the brightness. Since we're
# darkening the rolling window with each frame, STEPSIZE ^ TRAIL needs
# to be almost 0. Taking from the original script's idea of linearly
# darkening the frames, we demand STEPSIZE ^ TRAIL =
# (100/TRAIL). foo.py calculates STEPSIZE, given TRAIL.
STEPSIZE=$(python - <<EOF
import os
frames = int(os.environ["TRAIL"])

print(int(100 *( 1.0 - (1.0/frames) ** (1.0/frames))))

EOF
)

FINAL_DARKENING=$((100-${STEPSIZE}))

cp black-1.png rolling-window.png
# Initialize the "rolling window" trail image
for index in $(seq 2 ${TRAIL})
do
  # darken the entire window
  mogrify -brightness-contrast -${STEPSIZE}% rolling-window.png
  # add the next black-n.png (well, Screen, not Add)
  composite -compose Screen rolling-window.png black-${index}.png rolling-window.png
done


# Iterate over all frames, cheating with the start number, so I don't have to add extra handling for the first few frames.
echo "Creating light trails for $NUMBEROFFRAMES frames:"
for FRAME in $(seq $((${TRAIL}+1)) ${NUMBEROFFRAMES})
do
	  echo -n "$FRAME "
    # remove the oldest frame from the rolling window

    # Screen is 1-(1-src)*(1-dst)
    #
    # So to remove an image, we need to calculate
    # 1-((1-rolling_window)/(1-old_image))
    REMOVE=$((${FRAME}-${TRAIL}))
    convert -brightness-contrast -${FINAL_DARKENING}% black-${REMOVE}.png tmp-${FRAME}.png
    mogrify -negate tmp-${FRAME}.png

    cp rolling-window.png tmp2-${FRAME}.png
    composite -compose ColorBurn tmp-${FRAME}.png rolling-window.png rolling-window.png

    # darken the remaining window
    mogrify -brightness-contrast -${STEPSIZE}% rolling-window.png

    # Add the rolling window (containing the "black-" versions of Frames FRAME-TAIL to FRAME-1)
    # to the current frame
    composite -compose Screen rolling-window.png out-${FRAME}.png fused-${FRAME}.png

    # add the next "black" frame to the rolling window
    composite -compose Screen rolling-window.png black-${FRAME}.png rolling-window.png
    cp rolling-window.png window-${FRAME}.png
done
echo 'Done.'
ffmpeg -start_number $TRAIL -i fused-%d.png ${CURDIR}/${VIDEO_OUT}
cd ${CURDIR}
echo $TEMP

