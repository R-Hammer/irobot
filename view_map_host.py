#!/usr/bin/env python3
import cv2
import yaml
import sys

pgm_file = sys.argv[1] if len(sys.argv) > 1 else "test_map.pgm"
yaml_file = pgm_file.replace('.pgm', '.yaml')

# Read metadata
with open(yaml_file) as f:
    meta = yaml.safe_load(f)

print(f"\n{'='*50}")
print(f"SLAM Map: {pgm_file}")
print(f"{'='*50}")
print(f"Resolution:    {meta['resolution']} m/pixel")
print(f"Dimensions:    {meta['width']} × {meta['height']} pixels")
print(f"Size:          {meta['width'] * meta['resolution']:.1f} × {meta['height'] * meta['resolution']:.1f} m")
print(f"Origin (x,y):  ({meta['origin']['x']:.2f}, {meta['origin']['y']:.2f})")
print(f"{'='*50}\n")

# Show the image
img = cv2.imread(pgm_file, cv2.IMREAD_GRAYSCALE)
if img is None:
    print(f"Error: Could not load {pgm_file}")
    sys.exit(1)

cv2.imshow("SLAM Map Visualization", img)
print("Press any key to close...")
cv2.waitKey(0)
cv2.destroyAllWindows()