// this code takes an open hyperstack (3D + color + time) and deskews, scales (if necessary) rotates, and crops it on the GPU
// since CLIJ2 3D rotation requires an isotropic voxel size, the final image is scaled to the smallest pixel dimension

//user-defined parameters
rotation_angle_deg = 26.7; // rotation angle of the light sheet (_\) in degrees
cl_device = ""; //openCL-compatible device for CLIJ2. Enter a specific device (e.g. a GPU); otherwise, it selects the default
project = true; // whether or not to output three orthogonal maximum intensity projections

// start CLIJ2 on GPU, clear memory
run("CLIJ2 Macro Extensions", "cl_device="+cl_device);
Ext.CLIJ2_clear();
run("Collect Garbage");

// get current image info
getDimensions(im_width, im_height, im_channels, im_depth, im_frames); // size of 5D image
bit_depth = bitDepth(); // bit depth of the image
image_name = getInfo("window.title"); // set input image for CLIJ2 to deskew/rotate
rename("image1");
image1 = "image1";
getVoxelSize(px_width, px_height, px_step, px_unit);

// calculate deskew step size
rotation_angle_rad = rotation_angle_deg * PI/180;
px_depth = px_step*Math.sin(rotation_angle_rad);
px_deskew = sqrt(pow(px_step, 2) - pow(px_depth, 2));
deskew_step = px_deskew/px_height; // how many pixels to shear each slice by

// calculate scaling factors 
px_min = minOf(px_depth, minOf(px_width, px_height)); // smallest pixel dimension
width_scale = px_min/px_width; 
height_scale = px_min/px_height;
depth_scale = px_min/px_depth;

// pad skew dimension with zeros
new_width = 	Math.ceil(width_scale*	im_width);
new_height =	Math.ceil(height_scale*	im_height*Math.cos(rotation_angle_rad) + im_depth*depth_scale/Math.sin(rotation_angle_rad));
new_depth = 	Math.ceil(height_scale*	im_height*Math.sin(rotation_angle_rad));

// iterate over all timepoints
for (t = 0; t < im_frames; t++) { 
	selectWindow(image1);
	Stack.setFrame(1); // set to first timepoint
	
	// iterate over all channels
	for (c = 0; c < im_channels; c++) { 
		
		selectWindow(image1); 
		if (im_channels > 1) {
			Stack.setChannel(c+1) // set current channel
		}
		
		Ext.CLIJ2_push(image1); // put current XYZ stack to the GPU
		
		// create result image
		Ext.CLIJ2_create3D(image2, new_width, new_height, new_depth, bit_depth);
		
		// deskew, scale if necessary, and then rotate
		transform = "shearYZ=-"+deskew_step+" scaleX="+width_scale+" scaleY="+height_scale+" scaleZ="+depth_scale+" rotateX=-"+rotation_angle_deg+" translateZ=-"+new_depth;
		Ext.CLIJ2_affineTransform3D(image1, image2, transform); 
		
		// perform optional orthogonal projections 
		if (project) {
			// establish output images
			max_X = 		"max_X";
			max_X_flip = 	"max_X_flip";
			max_Y = 		"max_Y";
			max_Y_flip = 	"max_Y_flip";
			max_Z = 		"max_Z";
			max_ZX = 		"max_ZX";
			max_all = 		"max_t="+t+"_c="+c;
			// perform the projection, flip the X and Y projections
			Ext.CLIJ2_maximumXProjection(image2, max_X);
			Ext.CLIJ2_flip2D(max_X, max_X_flip, true, false); // flip X projection along X axis. puts coverslip at the bottom of the image
			Ext.CLIJ2_maximumYProjection(image2, max_Y);
			Ext.CLIJ2_flip2D(max_Y, max_Y_flip, false, true); // flip Y projection along Y axis. puts coverslip at the bottom of the image
			Ext.CLIJ2_maximumZProjection(image2, max_Z);
			// combine the images in quadrants. Z projection in upper left, Y projection in lower left, X projection in upper right. Empty in lower left.
			Ext.CLIJ2_combineHorizontally(max_Z, max_X_flip, max_ZX);
			Ext.CLIJ2_combineVertically(max_ZX, max_Y_flip, max_all);
		}

		// pull deskewed/scaled/rotated XYZ stack from GPU
		Ext.CLIJ2_pull(image2);
		rename("t="+t+"_c="+c);
		if (project) {
			Ext.CLIJ2_pull(max_all);
		}
		
	}
	
	// merge channels at current timepoint
	if (im_channels == 1) {
		selectWindow("t="+t+"_c=0");
		rename("t="+t);
		if (project) {
			selectWindow("max_t="+t+"_c=0");
			rename("max_t="+t);
		}
	} else if (im_channels == 2) { // this is my preferred color scheme
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		run("Merge Channels...", "c2="+green+" c6="+magenta+" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			run("Merge Channels...", "c2="+green+" c6="+magenta+" create ignore");
			rename("max_t="+t);
		}
	} else if (im_channels == 3) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta+" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			cyan = 		"max_t="+t+"_c=2";
			run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta+" create ignore");
			rename("max_t="+t);
		}
	} else if (im_channels == 4) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		yellow = 	"t="+t+"_c=3";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta+" c7="yellow+" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			cyan = 		"max_t="+t+"_c=2";
			yellow = 	"max_t="+t+"_c=3";
			run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta+" c7="yellow+" create ignore");
			rename("max_t="+t);
		}
	}
	
	// rename current timepoint
	if(t == 0) {
		selectWindow("t="+t);
		rename(image1+"_deskewed_rotated");
		if (project) {
			selectWindow("max_t="+t);
			rename(image1+"_deskewed_rotated_projected");
		}
	}
	
	// concatenate current timepoint to running stack
	if (t > 0) {
		run("Concatenate...", "  title="+image1+"_deskewed_rotated image1="+image1+"_deskewed_rotated image2=t="+t+" image3=[-- None --]");
		if (project) {
			run("Concatenate...", "  title="+image1+"_deskewed_rotated_projected image1="+image1+"_deskewed_rotated_projected image2=max_t="+t+" image3=[-- None --]");
		}
	}
	
	// we don't need the current timepoint, so remove it to conserve memory
	selectWindow(image1);
	if (t < im_frames-1) {
		run("Delete Slice", "delete=frame");
	} else {
		close();
	}
}

// convert stack to hyperstack
selectWindow(image1+"_deskewed_rotated");
run("Stack to Hyperstack...", "order=xyczt(default) channels="+im_channels+" slices="+new_depth+" frames="+im_frames+" display=Grayscale");
if (im_channels == 1) {
	run("Grays");
} else {
	Property.set("CompositeProjection", "null");
	Stack.setDisplayMode("grayscale");
}
run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);
rename(image_name+"deskewed_rotated");

// clean up projection if necessary
if (project) {
	selectWindow(image1+"_deskewed_rotated_projected");
	if (im_channels == 1) {
		run("Grays");
	} else {
		Property.set("CompositeProjection", "null");
		Stack.setDisplayMode("grayscale");
	}
	run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);
	rename(image_name+"deskewed_rotated_projected");
}

// clear memory
Ext.CLIJ2_clear();
run("Collect Garbage");
