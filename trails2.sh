#!/bin/bash
set -e
set -o nounset
set -o pipefail

# cut a video into frames, fuse the pictures into a running average, and throw them back into a video.
# Goal: Elongate light trails

VIDEO_IN=$1

# Number of frames to be fused; length of trail
TRAIL=$2

VIDEO_OUT=$(basename $VIDEO_IN .mp4)_${TRAIL}f.mp4

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

# STEPSIZE will be used to decrease the brightness. Spreading it evenly over the trail length sounds like a good idea.
export STEPSIZE=$((100/$TRAIL))

# Iterate over all frames, cheating with the start number, so I don't have to add extra handling for the first few frames.
echo "Creating light trails for $NUMBEROFFRAMES frames:"
for FRAME in $(seq $TRAIL $NUMBEROFFRAMES)
do
	echo -n "$FRAME "
  export FRAME
	# Take (FRAME minus index) and reduce the brightness by (index * stepsize) -> to tmp-(index).png
  # We can do this in parallel and save a bit of time
  seq 1 $((${TRAIL}-1)) | parallel 'convert -brightness-contrast $(({} * $STEPSIZE * -1))% black-$((${FRAME}-{})).png tmp-{}.png'
	ln -f out-${FRAME}.png tmp-fused-0.png
	for index in $(seq 1 $((${TRAIL}-1)))
	do
		# Take (FRAME minus index) and reduce the brightness by (index * stepsize) -> to tmp-(index).png
		# convert -brightness-contrast $(($index * $STEPSIZE * -1))% black-$((${FRAME}-${index})).png tmp-${index}.png 
		# add this darker layer first to the original image, later to the results of previous loops
		composite -compose Screen tmp-fused-$(($index-1)).png tmp-${index}.png tmp-fused-${index}.png
	done
	cp tmp-fused-${index}.png fused-${FRAME}.png
done
echo 'Done.'
ffmpeg -start_number $TRAIL -i fused-%d.png ${CURDIR}/${VIDEO_OUT}
cd ${CURDIR}
echo $TEMP
