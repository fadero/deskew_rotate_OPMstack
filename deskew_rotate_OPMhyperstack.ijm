// this code takes an open hyperstack (3D + color + time) and deskews/rotates it 

//user-defined parameters
rotation_angle_deg = 26.7; // rotation angle of the light sheet (_\) in degrees

// start CLIJ2 on GPU, clear memory
run("CLIJ2 Macro Extensions", "cl_device=[NVIDIA RTX A5000]");
Ext.CLIJ2_clear();
run("Collect Garbage");

// get current image info
getDimensions(im_width, im_height, im_channels, im_slices, im_frames); // size of 5D image
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
new_width = Math.ceil(width_scale*im_width);
new_height = Math.ceil(height_scale*(im_height + deskew_step*im_slices));
run("Canvas Size...", "width="+new_width+" height="+new_height+" position=Top-Center zero");

// pad depth dimension with zeros if necessary
if (depth_scale > 1) {
	new_slices = Math.ceil(im_slices*depth_scale);
	if (new_slices > im_slices) {
		for (i = 0; i < (new_slices - im_slices); i++) {
			Stack.setSlice(im_slices);
			run("Add Slice", "add=slice"); 
		}
	}
}

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
		
		// create result image and deskew/rotate
		image2 = "t="+t+"_c="+c; // name the output image
		transform = "scaleX="+width_scale+" scaleY="+height_scale+" scaleZ="+depth_scale+" shearYZ=-"+height_scale*deskew_step+" -center rotateX=-"+rotation_angle_deg+" center"; // define the transform
		Ext.CLIJ2_affineTransform3D(image1, image2, transform); // do the transform
		
		// pull deskewed/rotated XYZ stack from GPU
		Ext.CLIJ2_pull(image2);
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
	
	// we don't need the current timepoint, so remove it
	selectWindow(image1);
	if (t < im_frames-1) {
		run("Delete Slice", "delete=frame");
	} else {
		close();
	}
	
}

// convert stack to hyperstack
run("Grays");
run("Stack to Hyperstack...", "order=xyczt(default) channels="+im_channels+" slices="+new_slices+" frames="+im_frames+" display=Grayscale");
run("Set Scale...", "distance=1 known="+px_min+" unit="+px_unit);

// crop excess voxels in new stack
slices_toremove = new_slices - Math.ceil(im_height*height_scale*sin(rotation_angle_rad));
rows_toremove = new_height - Math.ceil(im_height*height_scale*cos(rotation_angle_rad) + new_slices/sin(rotation_angle_rad));

if (slices_toremove > 0) { // if there are too many slices in the new stack
	
	for (i = 0; i < Math.floor(slices_toremove/2); i++) {
		Stack.setSlice(new_slices - i);
		run("Delete Slice", "delete=slice");
	}
	
	for (i = 0; i < Math.floor(slices_toremove/2); i++) {
		Stack.setSlice(1)
		run("Delete Slice", "delete=slice");
	}
} else if (rows_toremove > 0) { // if there are too many rows in the new stack
	run("Canvas Size...", "width="+new_width+" height="+(new_height-rows_toremove)+" position=Center zero");
}

// rename new hyperstack and clear memory
rename(image_name+"_deskewed_rotated");
Ext.CLIJ2_clear();
run("Collect Garbage");