// This code takes an open hyperstack (3D + color + time) and deskews, 
// scales (if necessary), rotates it on the GPU.
// Since CLIJ2 3D rotation requires an isotropic voxel size,
// the final pixel size is scaled to the smallest pixel dimension.

//user-defined parameters
rotation_angle_deg = 26.7; // light sheet rotation angle (_\) in degrees
cl_device = ""; //openCL-compatible device for CLIJ2. Selects default.
project = true; // outputs three orthogonal max intensity projections
conserve_memory = false; // slows the code down slightly

// start CLIJ2 on GPU, clear memory
run("CLIJ2 Macro Extensions", "cl_device="+cl_device);
Ext.CLIJ2_clear();
run("Collect Garbage");

// get current image info
getDimensions(im_width, im_height, im_channels, im_depth, im_frames);
// size of 5D image
bit_depth = bitDepth(); // bit depth of the image
image_name = getInfo("window.title"); // set input image
rename("image1");
image1 = "image1";
getVoxelSize(px_width, px_height, px_step, px_unit);

// calculate deskew step size
rotation_angle_rad = rotation_angle_deg * PI/180;
px_depth = px_step*Math.sin(rotation_angle_rad);
px_deskew = sqrt(pow(px_step, 2) - pow(px_depth, 2));
deskew_step = px_deskew/px_height;

// calculate scaling factors 
px_min = minOf(px_depth, minOf(px_width, px_height)); 
// smallest pixel dimension; this will be the final voxel size
width_scale = px_min/px_width; // calculate each dimension scale factor
height_scale = px_min/px_height;
depth_scale = px_min/px_depth;

// calculate the new image size
new_width  = Math.ceil(width_scale*	im_width); // doesn't change
new_height = Math.ceil(height_scale*im_height*
			 		   Math.cos(rotation_angle_rad) + 
			 		   im_depth*depth_scale / 
			 		   Math.sin(rotation_angle_rad)); // new Y dimension
new_depth =  Math.ceil(height_scale*im_height*
			 		   Math.sin(rotation_angle_rad)); // new Z dimension

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
		Ext.CLIJ2_create3D(image2, new_width, new_height, new_depth, 
							bit_depth);
		
		// deskew, scale if necessary, rotate, then reposition image
		transform = "shearYZ=-"+deskew_step+" scaleX="+width_scale+
					" scaleY="+height_scale+" scaleZ="+depth_scale+
					" rotateX=-"+rotation_angle_deg+" translateZ=-"+
					new_depth;
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
			// perform the projections
			Ext.CLIJ2_maximumXProjection(image2, max_X);
			Ext.CLIJ2_maximumYProjection(image2, max_Y);
			Ext.CLIJ2_maximumZProjection(image2, max_Z);
			// flip X projection along X axis. puts coverslip at bottom
			Ext.CLIJ2_flip2D(max_X, max_X_flip, true, false); 
			// flip Y projection along Y axis. puts coverslip at right
			Ext.CLIJ2_flip2D(max_Y, max_Y_flip, false, true); 
			// combine the images in quadrants. 
			// Z projection in upper left
			// Y projection in lower left
			// X projection in upper right. Empty in lower left.
			Ext.CLIJ2_combineHorizontally(max_Z, max_X_flip, max_ZX);
			Ext.CLIJ2_combineVertically(max_ZX, max_Y_flip, max_all);
		}

		// pull deskewed/scaled/rotated XYZ stack from GPU
		Ext.CLIJ2_pull(image2);
		rename("t="+t+"_c="+c);
		// pull projections if necessary
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
		run("Merge Channels...", "c2="+green+" c6="+magenta+
		" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			run("Merge Channels...", "c2="+green+" c6="+magenta+
			" create ignore");
			rename("max_t="+t);
		}
	} else if (im_channels == 3) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+
		magenta+" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			cyan = 		"max_t="+t+"_c=2";
			run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+
			magenta+" create ignore");
			rename("max_t="+t);
		}
	} else if (im_channels == 4) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		yellow = 	"t="+t+"_c=3";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+
		magenta+" c7="yellow+" create ignore");
		rename("t="+t);
		if (project) {
			green = 	"max_t="+t+"_c=0";
			magenta =	"max_t="+t+"_c=1";
			cyan = 		"max_t="+t+"_c=2";
			yellow = 	"max_t="+t+"_c=3";
			run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+
			magenta+" c7="yellow+" create ignore");
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
		run("Concatenate...", "  title="+image1+
		"_deskewed_rotated image1="+image1+
		"_deskewed_rotated image2=t="+t+" image3=[-- None --]");
		if (project) {
			run("Concatenate...", "  title="+image1+
			"_deskewed_rotated_projected image1="+image1+
			"_deskewed_rotated_projected image2=max_t="+t+
			" image3=[-- None --]");
		}
	}
	
	if (conserve_memory) {
		// we don't need the current timepoint, so delete it
		selectWindow(image1);
		if (t < im_frames-1) {
			run("Delete Slice", "delete=frame");
		} else {
			close();
		}
		run("Collect Garbage");
	}
}

// convert stack to hyperstack
selectWindow(image1+"_deskewed_rotated");
run("Stack to Hyperstack...", "order=xyczt(default) channels="
	+im_channels+" slices="+new_depth+" frames="+im_frames+
	" display=Grayscale");

// set composite image to grayscale
if (im_channels == 1) {
	run("Grays");
} else {
	Property.set("CompositeProjection", "null");
	Stack.setDisplayMode("grayscale");
}

// change the pixel scale metadata
run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);
rename(image_name+"_deskewed_rotated");

// change the name of the original image back, if it exists
if (!conserve_memory) {
	selectWindow(image1);
	rename(image_name);
}

// clean up projections if necessary, same steps as above
if (project) {
	selectWindow(image1+"_deskewed_rotated_projected");
	if (im_channels == 1) {
		run("Grays");
	} else {
		Property.set("CompositeProjection", "null");
		Stack.setDisplayMode("grayscale");
	}
	run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);
	rename(image_name+"_deskewed_rotated_projected");
}

// clear memory
Ext.CLIJ2_clear();
run("Collect Garbage");
