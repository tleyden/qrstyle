#!/usr/bin/env ruby

require 'rubygems'
require 'RMagick'
include Magick
require 'rqrcode'
require 'ruby-debug'
require 'signature_color_map'

# Generates customized, stylized qr codes with an embedded logo in the center (see ../samplegallery)
# Usage: $ ruby qrstyle.rb
# 
# Currently takes no args, as the customization happens in the code..

class QRStyle

	# create a new QRStyle object which can generate qrcode images
	# Params:
	# +config+:: the configuration dictionary which contains the following keys:
	#            :square_size_px => 5 (the size in pixels of each square in the qrcode matrix)
	#            :debug => false (spit out useful debug info?)
	#            :square_color => "#a59140" (what color should each square be?  assuming no :square_color_map passed in)
	#            :square_color_map => [1d or 2d array of color strings] if its 2d, it exactly specifies the color of each square.
	#                                  if its only 1d, that color map will be applied for every row.  WARN: if the 
	#                                  square_color_map size does not match with the qrcode_matrix.module_count (eg, 33), 
	#                                  then it won't be colored correctly.  Not sure how to best deal with that elegantly..
	def initialize(config)
		@config=config
	end

	# return a qr code PNG image for the given string to encode and given logo PNG to embed
	# Params:
	# +qrstring+:: the string to be encoded in qrcode
	# +logo_image+:: an rmagick +Image+ object which represents the logo image
	def generate(qrstring, logo_image)

		# get the QRCode matrix object from rQrCode
		qrcode_matrix = self.generate_qrcode_matrix(qrstring)

		# Create a completely transparent image with dimensions of target image		
		image_width = self.image_width_pixels(qrcode_matrix.module_count) 
		transparent_img = Image.new(image_width,image_width) { self.background_color = "transparent" }

		# Center the logo in the transparent image created above
		qr_logo_raw_overlay_img = transparent_img.composite(logo_image, CenterGravity, OverCompositeOp)

		# Modify the qr code squares and whiten all squares which are overlapped by non-transparent areas of logo
		self.whiten_overlapped_squares(qrcode_matrix.modules, qr_logo_raw_overlay_img)

		# Generate the qr code image based on modified modules matrix
		qr_code_image = self.generate_qr_code_image(qrcode_matrix)

		# Composite with the logo overlay
		qr_code_image_plus_logo = qr_code_image.composite(qr_logo_raw_overlay_img, CenterGravity, OverCompositeOp)

		# Wrap in larger image to provide 1-square white margin
		image_width = ((qrcode_matrix.module_count + 2) *  @config[:square_size_px])
		transparent_img_margin = Image.new(image_width,image_width) { self.background_color = "white" }
		qr_code_logo_plus_margin = transparent_img_margin.composite(qr_code_image_plus_logo, CenterGravity, OverCompositeOp)

		return qr_code_logo_plus_margin
	
	end

	# get the qr code matrix for this input string with "high" redundancy so we can embed a logo
	# note: don't specify :size, let it figure out which "version" to use for us (version determines 
	# number of modules/squares)
	# Params:
	# +qrstring+:: the string to be encoded in qrcode	
	def generate_qrcode_matrix(qrstring)

		qrcode_matrix = RQRCode::QRCode.new(qrstring, :level => :h )

		if @config[:debug]  # debugging
			debug_image_name = "../testdata/qr_code_image_before_modification.png" 
			qr_code_image = self.generate_qr_code_image(qrcode_matrix)
			qr_code_image.write(debug_image_name)
			puts "Writing debug image: #{debug_image_name}" 
		end

		return qrcode_matrix

	end

	# generate the qr code image based on the modules passed in
	# Params:
	# +qrcode_matrix+:: the +QrCode+ object from the +rQrCode+ library 
	def generate_qr_code_image(qrcode_matrix)

		square_width = @config[:square_size_px]
		square_height = @config[:square_size_px]

		image_width = qrcode_matrix.module_count * square_width
		image_height = image_width

		# Create a completely transparent image as a starting point
		qr_code_img = Image.new(image_width,image_height) { self.background_color = "transparent" }

		# Loop over every QR code square
		qrcode_matrix.modules.each_index do |row| 
			qrcode_matrix.modules.each_index do |col| 

				# create the black or white square image
				if qrcode_matrix.dark?(row,col)
					bgcolor = self.get_dark_square_color(row,col)
				else
					bgcolor = "white"					
				end
				square_img = Image.new(square_width,square_height) { self.background_color = bgcolor }
				square_img_pixels = square_img.get_pixels(0,0,square_width,square_height)

				# draw the square into the qr_code_img result
				y = row * square_height  
				x = col * square_width
				qr_code_img.store_pixels(x,y,square_width,square_height,square_img_pixels)

			end
		end

		if @config[:debug]  # debugging
			debug_image_name = "../testdata/qr_code_image_before_overlay.png" 
			qr_code_img.write(debug_image_name)
			puts "Writing debug image: #{debug_image_name}" 
		end

		return qr_code_img

	end

	# what color should we use for this dark square?  depends on the configuration passed in
	# and the row and col
	# Params:
	# +row+:: the current row in the matrix
	# +row+:: the current col in the matrix
	# Returns:
	# a string representing the color, eg "black" or "#a59140".  see imagemagick docs.
	def get_dark_square_color(row,col)

		square_color_map = @config[:square_color_map]

		# were we passed a color map?
		if (square_color_map && square_color_map.kind_of?(Array)) 

			# is it a 2d array?
			if (square_color_map[0].kind_of?(Array))
				return square_color_map[row][col] || "black"	
			else
				# nope, its a 1d array, so this array applies for every row
				return square_color_map[col] || "black"
			end

		else
			# no color map passed, fall back to simple square_color config val 
			return @config[:square_color] || "black"
		end


	end


	# the width in pixels of the image that will be generated.  since its a square, width==height
	# Params:
	# +module_count+:: the number of qrcode modules (squares) present in the qrcode image.  longer strings == more qrcode modules
	def image_width_pixels(module_count)

		return module_count * @config[:square_size_px]

	end

	# Modify the qr code squares and whiten all squares which are overlapped by non-transparent areas of logo,
	# even if the square is only overlapped by a single non-transparent pixel from logo.  The modules parameter
	# will be modified in place
	# Params:
	# +modules+:: the matrix returned from rQrCode which specfies which modules (squares) are dark squares
	# +logo_overlay_image+:: the logo which has been centered on a transparent image the size of target qr code image
	def whiten_overlapped_squares(modules, logo_overlay_image)

		square_width = @config[:square_size_px]
		square_height = @config[:square_size_px]

		# Loop over every QR code square
		modules.each_index do |row| 
			modules.each_index do |col| 

				# 	Get sub-image in qr_logo_raw_overlay_img which corresponds to that QR code square
				y = row * square_height  
				x = col * square_width
				subregion_qr_logo_pixels = logo_overlay_image.get_pixels(x,y,square_width,square_height)
				if @config[:debug]  # debugging
					debug_image = Image.new(square_width,square_height) { self.background_color = "transparent" }
					debug_image.store_pixels(0,0,square_width,square_height,subregion_qr_logo_pixels)
					debug_image_name = "../testdata/debug_#{row}_#{col}.png" 
					debug_image.write(debug_image_name)
					puts "Writing debug image: #{debug_image_name}" 
					 
					self.ever
				end

				# Does every pixel in subregionQrLogo have opacity=65535 (eg, completely transparent)?
				if not self.every_pixel_transparent subregion_qr_logo_pixels
					# the logo image has non-transparent pixels which overlap this square!
					# Modify appropriate square in qrcode_matrix and force it to be white
					modules[row][col] = false
					if @config[:debug]  # debugging
						puts "Found non transparent region at (#{row}, #{col})"
					end
				end
			end
		end
	end

	# Does every pixel in subregionQrLogo have opacity=65535 (eg, completely transparent)?
	# Params:
	# +image_region_pixel_array+:: an rmagick array of pixels which represents the image region being checked
	# Returns:
	# +return_val+:: true if region is completely transparent, false otherwise
	def every_pixel_transparent(image_region_pixel_array)
		found_non_transparent = false
		image_region_pixel_array.each do |pixel|
			if pixel.opacity != 65535
				found_non_transparent = true	
			end
		end
		return !found_non_transparent
	end



end

puts "start"
testlogo = ImageList.new('../testdata/testlogo_signature_4.png')[0]
rolex_config = {:square_size_px => 5, :debug => false, :square_color => "#a59140"}
signature_config = {:square_size_px => 12, :debug => false, :square_color_map => $signature_color_map} 
misc_config = {:square_size_px => 12, :debug => false, :square_color => "#BA0038"}  
qrstyle = QRStyle.new(signature_config)
qrcodeimg = qrstyle.generate("http://getsignature.com", testlogo)
image_name = "../testdata/qr_code_image_final.png" 
qrcodeimg.write(image_name)
puts "Writing final result image: #{image_name}"
puts qrcodeimg
puts "done"