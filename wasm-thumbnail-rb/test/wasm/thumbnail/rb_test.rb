# frozen_string_literal: true

require "test_helper"

class Wasm::Thumbnail::RbTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Wasm::Thumbnail::Rb::VERSION
  end

  def test_it_does_something_useful
    wasm_instance = Wasm::Thumbnail::Rb::GetWasmInstance.call

    size = 250_000
    file_bytes = File.binread("#{__dir__}/brave.png").unpack("C*")
    dimensions = [100, 200]

    # This tells us how much space we'll need to put our image in the WASM env
    image_length = file_bytes.length
    input_pointer = wasm_instance.exports.allocate.call(image_length)
    # Get a pointer on the allocated memory so we can write to it
    memory = wasm_instance.exports.memory.uint8_view input_pointer

    # Put the image to resize in the allocated space
    (0..image_length - 1).each do |nth|
      memory[nth] = file_bytes[nth]
    end

    # Do the actual resize and pad
    # Note that this writes to a portion of memory the new JPEG file, but right pads the rest of the space
    # we gave it with 0.
    output_pointer = wasm_instance
                     .exports.resize_and_pad
                     .call(input_pointer, image_length, dimensions[0], dimensions[1], size)

    # Get a pointer to the result
    memory = wasm_instance.exports.memory.uint8_view output_pointer

    # Only take the buffer that we told the rust function we needed. The resize function
    # makes a smaller image than the buffer we said, and then pads out the rest so we have to
    # go hunting for the bytes which represent the JPEG image. In hex, JPEG images start with
    # FFD8 and FFD9, so we can convert to hex and find the bounds of the image, then write to file
    bytes = memory.to_a.take(size)

    # Deallocate
    wasm_instance.exports.deallocate.call(input_pointer, image_length)
    wasm_instance.exports.deallocate.call(output_pointer, bytes.length)

    # The bytes passed back to us are ASCII-encoded, i.e. 8bit bytes. Interpret them as so,
    # and THEN convert to hex to search for the image bytes

    # The first 4 bytes are a header until the image. The actual image probably ends well before
    # the whole buffer, but we keep the junk data on the end to make all the images the same size
    # for privacy concerns.
    image = bytes[4..].pack("C*")

    puts "Image resized and padded to size #{image.length}"
  end
end
