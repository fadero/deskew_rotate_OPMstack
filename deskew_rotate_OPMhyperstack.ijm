// this code takes an open hyperstack (3D + color + time) and deskews, scales (if necessary) rotates, and crops it on the GPU
// since CLIJ2 3D rotation requires an isotropic voxel size, the final image is scaled to the smallest pixel dimension

//user-defined parameters
rotation_angle_deg = 26.7; // rotation angle of the light sheet (_\) in degrees
cl_device = "[NVIDIA RTX A5000]"; //openCL-compatible device for CLIJ2. Example GPU defined here. 

// start CLIJ2 on GPU, clear memory
run("CLIJ2 Macro Extensions", "cl_device="+cl_device);
Ext.CLIJ2_clear();
run("Collect Garbage");

// get current image info
getDimensions(im_width, im_height, im_channels, im_depth, im_frames); // size of 5D image
image_name = getInfo("window.title"); // set input image for CLIJ2 to deskew/rotate
rename("image1");
image1 = "image1";
getVoxelSize(px_width, px_height, px_step, px_unit);

// calculate deskew step size
rotation_angle_rad = rotation_angle_deg * PI/180;
px_depth = px_step*sin(rotation_angle_rad);
px_deskew = sqrt(pow(px_step, 2) - pow(px_depth, 2));
deskew_step = px_deskew/px_height; // how many pixels to shear each slice by

// calculate scaling factors 
px_min = minOf(px_depth, minOf(px_width, px_height)); // smallest pixel dimension
width_scale = px_width/px_min; 
height_scale = px_height/px_min;
depth_scale = px_depth/px_min;

// pad skew dimension with zeros
new_width = 	Math.ceil(width_scale*	im_width);
new_height =	Math.ceil(height_scale*(im_height + deskew_step*im_depth));
new_depth = 	Math.ceil(depth_scale*	im_depth);

// pre-determine how we need to crop the final image
slices_toremove = maxOf(0, new_depth - Math.ceil(im_height*height_scale*sin(rotation_angle_rad)));
rows_toremove = maxOf(0, new_height - Math.ceil(im_height*height_scale*cos(rotation_angle_rad) + new_depth/sin(rotation_angle_rad)));

// calculate how big our final 3D stack should be
final_width 	= new_width;
final_height 	= new_height - 2*Math.floor(rows_toremove/2);
final_depth 	= new_depth -  2*Math.floor(slices_toremove/2);

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
		
		Ext.CLIJ2_push(image1); // put current XYZ stack to CLIJ2
		
		// create temp result image for padding
		image2 = "image2";
		
		// pad the input image along the skew axis
		Ext.CLIJ2_crop3D(image1, image2, 0, 0, 0, new_width, new_height, new_depth);
		
		// set padded pixels to zero
		row_start = Math.round(height_scale*im_height+1);
		row_end = new_height;
		for (i = 0; i < row_end-row_start; i++) {
			row_index = row_start+i;
			Ext.CLIJ2_setRow(image2, row_index, 0);
		}

		// deskew, scale if necessary, and then rotate
		image3 = "image3";
		transform = "shearYZ=-"+height_scale*deskew_step+" scaleX="+width_scale+" scaleY="+height_scale+" scaleZ="+depth_scale+" -center rotateX=-"+rotation_angle_deg+" center";
		Ext.CLIJ2_affineTransform3D(image2, image3, transform); 
		
		// name output image
		image4 = "t="+t+"_c="+c;
		
		// crop excess voxels in new stack
		Ext.CLIJ2_crop3D(image3, image4, 0, Math.floor(rows_toremove/2), Math.floor(slices_toremove/2), final_width, final_height, final_depth);

		// pull deskewed/scaled/rotated XYZ stack from GPU
		Ext.CLIJ2_pull(image4);
		Ext.CLIJ2_clear();
	}
	
	// merge channels at current timepoint
	if (im_channels == 2) { // this is my preferred color scheme
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		run("Merge Channels...", "c2="+green+" c6="+magenta);
	} else if (im_channels == 3) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta);
	} else if (im_channels == 4) {
		green = 	"t="+t+"_c=0";
		magenta = 	"t="+t+"_c=1";
		cyan = 		"t="+t+"_c=2";
		yellow = 	"t="+t+"_c=3";
		run("Merge Channels...", "c2="+green+" c5="+cyan+" c6="+magenta+" c7="yellow);
	}
	
	// rename current timepoint
	if(t == 0) {
		rename(image1+"_deskewed_rotated");
	} else {
		rename("t="+t);
	}
	
	// concatenate current timepoint to running stack
	if (t > 0) {
		run("Concatenate...", "  title="+image1+"_deskewed_rotated image1="+image1+"_deskewed_rotated image2=t="+t+" image3=[-- None --]");
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
run("Grays");
run("Stack to Hyperstack...", "order=xyczt(default) channels="+im_channels+" slices="+final_depth+" frames="+im_frames+" display=Grayscale");
run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);

// rename new hyperstack and clear memory
rename(image_name+"_deskewed_scaled_rotated");
Ext.CLIJ2_clear();
run("Collect Garbage");
