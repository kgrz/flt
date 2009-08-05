# Support classes for homogeneous treatment of BigDecimal and Num values by defining BigDecimal.context

require 'flt'
require 'bigdecimal'
require 'bigdecimal/math'

require 'singleton'

# Context class with some of the Flt::Num context functionality, to allow the use of BigDecimal numbers
# similarly to other Num values; this eases the implementation of functions compatible with either
# Num or BigDecimal values.
class Flt::BigDecimalContext

  include Singleton
  # TODO: Context class with precision, rounding, etc. (no singleton)

  def num_class
    BigDecimal
  end

  def Num(*args)
    args = *args if args.size==1 && args.first.is_a?(Array)
    if args.size > 1
      BigDecimal.new(DecNum(*args).to_s)
    else
      x = args.first
      case x
      when BigDecimal
        x
      when Rational
        BigDecimal(x.numerator.to_s)/BigDecimal(x.denominator.to_s)
      else
        BigDecimal.new(x.to_s)
      end
    end
  end

  def radix
    10
  end

  # NaN (not a number value)
  def nan
    BigDecimal('0')/BigDecimal('0')
  end

  def infinity(sign=+1)
    BigDecimal(sign.to_s)/BigDecimal('0')
  end

  def zero(sign=+1)
    BigDecimal("#{(sign < 0) ? '-' : ''}0")
  end

  def int_radix_power(n)
    10**n
  end

  def exact?
    BigDecimal.limit == 0
  end

  def precision
    BigDecimal.limit
  end

  ROUNDING_MODES = {
    BigDecimal::ROUND_UP=>:up,
    BigDecimal::ROUND_DOWN=>:down,
    BigDecimal::ROUND_CEILING=>:ceiling,
    BigDecimal::ROUND_FLOOR=>:floor,
    BigDecimal::ROUND_HALF_UP=>:half_up,
    BigDecimal::ROUND_HALF_DOWN=>:half_down,
    BigDecimal::ROUND_HALF_EVEN=>:half_even
  }

  def rounding
    ROUNDING_MODES[BigDecimal.mode(BigDecimal::ROUND_MODE, nil)]
  end

  # Sign: -1 for minus, +1 for plus, nil for nan (note that Float zero is signed)
  def sign(x)
    x.sign < 0 ? -1 : +1
  end

  # Return copy of x with the sign of y
  def copy_sign(x, y)
    self_sign = x.sign
    other_sign = y.is_a?(Integer) ? (y < 0 ? -1 : +1) : y.sign
    if self_sign && other_sign
      if self_sign == other_sign
        x.to_f
      else
        -x.to_f
      end
    else
      nan
    end
  end

  def split(x)
    sgn, d, b, e = x.split
    [sgn<0 ? -1 : +1, d.to_i, e-d.size]
  end

  # Return the value of the number as an signed integer and a scale.
  def to_int_scale(x)
    sgn, d, b, e = x.split
    c = d.to_i
    [sgn<0 ? -1 : c, -c, e-d.size]
  end

  def special?(x)
    x.nan? || x.infinite?
  end

  def plus(x)
    x
  end

  def minus(x)
    -x
  end

  class << self

    def big_decimal_method(*methods)
      methods.each do |method|
        if method.is_a?(Array)
          float_method, context_method = method
        else
          float_method = context_method = method
        end
        define_method(context_method) do |x|
          Num(x).send float_method
        end
      end
    end

  end

  big_decimal_method :nan?, :infinite?, :zero?, :abs

end

# Return a (limited) context object for BigDecimal.
# This eases the implementation of functions compatible with either Num or BigDecimal values.
def BigDecimal.context
  Flt::BigDecimalContext.instance
end

