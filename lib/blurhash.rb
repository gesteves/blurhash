# frozen_string_literal: true

require 'blurhash/version'
require 'blurhash_ext'

module Blurhash
  def self.encode(width, height, pixels, x_comp: 4, y_comp: 3)
    p = pixels.pack("C#{pixels.size}")
    return Unstable.blurHashForPixels(x_comp, y_comp, width, height, p)
  end

  # Decodes a blurhash into a matrix of pixels.
  # Returns an array of arrays of arrays,
  # for each row of pixels, each column of pixels,
  # and each pixel with 4 values in the range 0-255,
  # for the R, G, B, and alpha channels.
  # This can be passed directly to MiniMagick,
  # or flattened to be used with canvas.
  def self.decode(width, height, blurhash, punch: 1)
    size_flag = Base83.decode83(blurhash[0])
    num_y = (size_flag / 9.0).floor + 1
    num_x = (size_flag % 9) + 1

    quantised_maximum_value = Base83.decode83(blurhash[1])
    maximum_value = (quantised_maximum_value + 1) / 166.0

    colors = []

    (num_x * num_y).times do |i|
      if i == 0
        value = Base83.decode83(blurhash[2..5])
        colors << decode_dc(value)
      else
        value = Base83.decode83(blurhash[(4 + i * 2)..(5 + i * 2)])
        colors << decode_ac(value, maximum_value * punch)
      end
    end

    pixels = []

    height.times do |h|
      row = []
      width.times do |w|
        r = 0
        g = 0
        b = 0
        num_y.times do |y|
          num_x.times do |x|
            basis = Math.cos((Math::PI * w * x) / width.to_f) * Math.cos((Math::PI * h * y) / height.to_f)
            color = colors[x + y * num_x]
            r += color[0] * basis
            g += color[1] * basis
            b += color[2] * basis
          end
        end

        int_r = linear_to_srgb(r)
        int_g = linear_to_srgb(g)
        int_b = linear_to_srgb(b)

        row << [int_r, int_g, int_b, 255]

      end
      pixels << row
    end
    pixels
  end

    # Returns whether or not a given blurhash is valid.
  def self.valid_blurhash?(blurhash)
    return false if blurhash.blank? || blurhash.size < 6

    size_flag = Base83.decode83(blurhash[0])
    num_y = (size_flag / 9.0).floor + 1
    num_x = (size_flag % 9) + 1

    blurhash.size == 4 + 2 * num_x * num_y
  end

  def self.srgb_to_linear(value)
    v = value / 255.0
    if v <= 0.04045
      v/12.92
    else
      ((v + 0.055) / 1.055) ** 2.4
    end
  end

  def self.linear_to_srgb(value)
    v = value.clamp(0, 1)
    if (v <= 0.0031308)
      (v * 12.92 * 255 + 0.5).round
    else
      ((1.055 * (v ** (1 / 2.4)) - 0.055) * 255 + 0.5).round
    end
  end

  def self.sign(n)
    n < 0 ? -1 : 1
  end

  def self.sign_pow(val, exp)
    sign(val) * (val.abs ** exp)
  end

  def self.decode_dc(value)
    r = value >> 16
    g = (value >> 8) & 255
    b = value & 255
    [srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)]
  end

  def self.decode_ac(value, maximum)
    quant_r = (value / (19 * 19).to_f).floor
    quant_g = (value / 19.0).floor % 19
    quant_b = value % 19
    [sign_pow((quant_r - 9) / 9.0, 2) * maximum, sign_pow((quant_g - 9) / 9.0, 2) * maximum, sign_pow((quant_b - 9) / 9.0, 2) * maximum]
  end

  def self.components(str)
    size_flag = Base83.decode83(str[0])
    y_comp    = (size_flag / 9) + 1
    x_comp    = (size_flag % 9) + 1

    return if str.size != 4 + 2 * x_comp * y_comp

    [x_comp, y_comp]
  end

  module Base83
    DIGIT_CHARACTERS = %w(
      0 1 2 3 4 5 6 7 8 9
      A B C D E F G H I J
      K L M N O P Q R S T
      U V W X Y Z a b c d
      e f g h i j k l m n
      o p q r s t u v w x
      y z # $ % * + , - .
      : ; = ? @ [ ] ^ _ {
      | } ~
    ).freeze

    def self.decode83(str)
      value = 0

      str.each_char.with_index do |c, i|
        digit = DIGIT_CHARACTERS.find_index(c)
        value = value * 83 + digit
      end

      value
    end
  end

  private_constant :Unstable
end
