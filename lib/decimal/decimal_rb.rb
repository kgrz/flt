require 'bigdecimal'
require 'forwardable'
require 'rational'
require 'monitor'
require 'ostruct'

module FPNum

# Pure Ruby Decimal Implementation
module RB

# Decimal arbitrary precision floating point number.
class Decimal
  
  extend FPNum # allows use of unqualified FlagValues(), Flags()
  include RB # allows use of unqualified Decimal()  
  
  ROUND_HALF_EVEN = :half_even
  ROUND_HALF_DOWN = :half_down
  ROUND_HALF_UP = :half_up
  ROUND_FLOOR = :floor
  ROUND_CEILING = :ceiling
  ROUND_DOWN = :down
  ROUND_UP = :up
  ROUND_05UP = :up05
   
  # Numerical base of Decimal.
  def self.radix
    10
  end

  # Integral power of the base: radix**n for integer n; returns an integer.
  def self.int_radix_power(n)
    10**n
  end
  
  # Multiply by an integral power of the base: x*(radix**n) for x,n integer;
  # returns an integer.
  def self.int_mult_radix_power(x,n)
    x * (10**n)
  end  

  # Divide by an integral power of the base: x/(radix**n) for x,n integer;
  # returns an integer.
  def self.int_div_radix_power(x,n)
    x / (10**n)
  end  


  # Base class for errors
  class Error < StandardError
  end
  
  # All exception conditions derive from this class.
  class Exception < StandardError
    attr :context
    def initialize(context=nil)
      @context = context
    end
    
    # Defines the value returned when trapping is inactive
    # for the condition. The arguments are those passed to
    # Context#exception after the message.
    def self.handle(context, *args)
    end    
  end
  
  # Invalid operation exception.
  class InvalidOperation < Exception
    def self.handle(context=nil, *args)
      if args.size>0
        sign, coeff, exp = args.first.split
        Decimal.new([sign, exp, :nan])._fix_nan(context)
      else
        Decimal.nan
      end
    end
    def initialize(context=nil, *args)
      @value = args.first if args.size>0
      super
    end
  end
  
  class DivisionByZero < Exception
    def self.handle(context,sign,*args)
      Decimal.infinity(sign)
    end
    def initialize(context=nil, sign=nil, *args)
      @sign = sign      
      super
    end
  end

  class DivisionImpossible < Exception
    def self.handle(context,*args)
      Decimal.nan
    end
  end

  class DivisionUndefined < Exception
    def self.handle(context,*args)
      Decimal.nan
    end
  end
  
  class Inexact < Exception
  end
  
  class Overflow < Exception
    def self.handle(context, sign, *args)
      if [:half_up, :half_even, :half_down, :up].include?(context.rounding)
        Decimal.infinity(sign)
      elsif sign==+1
        if context.rounding == :ceiling
          Decimal.infinity(sign)
        else
          Decimal([sign, int_radix_power(context.precision) - 1, context.emax - context.precision + 1])
        end
      elsif sign==-1
        if context_rounding == :floor
          Decimal.infinity(sign)
        else
          Decimal([sign, int_radix_power(context.precision) - 1, context.emax - context.precision + 1])
        end
      end
    end
    def initialize(context=nil, sign=nil, *args)
      @sign = sign
      super
    end
  end
  
  class Underflow < Exception
  end
  
  # Clamped exception: exponent changed to fit bounds.
  class Clamped < Exception
  end
  
  class InvalidContext < Exception
    def self.handle(context,*args)
      Decimal.nan
    end
  end
  
  class Rounded < Exception
  end

  class Subnormal < Exception
  end
  
  class ConversionSyntax < InvalidOperation
    def self.handle(context, *args)
      Decimal.nan
    end
  end
  

  
  EXCEPTIONS = FlagValues(Clamped, InvalidOperation, DivisionByZero, Inexact, Overflow, Underflow, Rounded, Subnormal)

  def self.Flags(*values)
    FPNum::Flags(EXCEPTIONS,*values)
  end    
    

  # The context defines the arithmetic context: rounding mode, precision,...
  # Decimal.context is the current (thread-local) context.
  class Context
    
    include RB # allows use of unqualified Decimal()
    
    def initialize(options = {})
      
      # default context:
      @rounding = ROUND_HALF_EVEN
      @precision = 28
      
      @emin = -99999999 
      @emax =  99999999 # BigDecimal misbehaves with expoonents such as 999999999
      
      @flags = Decimal::Flags()
      @traps = Decimal::Flags()      
      @ignored_flags = Decimal::Flags()
      
      # currently unused here...
      @signal_flags = true # no flags updated if false
      @quiet = false # no traps or flags updated if ture
      
      @capitals = true
      
      @clamp = false
                  
      assign options
        
    end
    
    attr_accessor :rounding, :precision, :emin, :emax, :flags, :traps, :quiet, :signal_flags, :ignored_flags, :capitals, :clamp
    
    def ignore_all_flags
      #@ignored_flags << EXCEPTIONS
      @ignored_flags.set!      
    end
    def ignore_flags(*flags)
      #@ignored_flags << flags
      @ignored_flags.set(*flags)
    end
    def regard_flags(*flags)
      @ignored_flags.clear(*flags)
    end
    
    def etiny
      emin - precision + 1
    end
    def etop
      emax - precision + 1
    end
    
    def digits
      self.precision
    end
    def digits=(n)
      self.precision=n
    end
    def prec
      self.precision
    end
    def prec=(n)
      self.precision = n
    end
    def clamp?
      @clamp
    end
        
    def assign(options)
      @rounding = options[:rounding] unless options[:rounding].nil?
      @precision = options[:precision] unless options[:precision].nil?        
      @traps = Decimal::Flags(options[:rounding]) unless options[:rounding].nil?
      @ignored_flags = options[:ignored_flags] unless options[:ignored_flags].nil?
      @signal_flags = options[:signal_flags] unless options[:signal_flags].nil?
      @quiet = options[:quiet] unless options[:quiet].nil?
      @emin = options[:emin] unless options[:emin].nil?
      @emax = options[:emax] unless options[:emax].nil?
      @capitals = options[:capitals ] unless options[:capitals ].nil?
      @clamp = options[:clamp ] unless options[:clamp ].nil?
    end
    
    
    
    CONDITION_MAP = {
      ConversionSyntax=>InvalidOperation,
      DivisionImpossible=>InvalidOperation,
      DivisionUndefined=>InvalidOperation,
      InvalidContext=>InvalidOperation
    }
    
    def exception(cond, msg='', *params)      
      err = (CONDITION_MAP[cond] || cond)      
      return err.handle(self, *params) if @ignored_flags[err]                      
      @flags << err # @flags[err] = true
      return cond.handle(self, *params) if !@traps[err]            
      raise err.new(*params), msg
    end
    
    def add(x,y)
      x.add(y,self)
    end
    def substract(x,y)
      x.substract(y,self)
    end
    def multiply(x,y)
      x.multiply(y,self)
    end
    def divide(x,y)
      x.divide(y,self)
    end
    
    def abs(x)
      x.abs(self)
    end
    
    def plus(x)
      x._pos(self)
    end
    
    def minus(x)
      x._neg(self)
    end
    
    def to_string(eng=false)
      x.to_s(eng, self)
    end

    def reduce(x)
      x.reduce(self)
    end
    

    # Adjusted exponent of x returned as a Decimal value.
    def logb(x)
      Decimal(x.adjusted_exponent,self)
    end
    
    # x*(radix**y) y must be an integer
    def scaleb(x, y)
      Decimal(x).scaleb(y,self)      
    end
        
    
    # Exponent in relation to the significand as an integer
    # normalized to precision digits. (minimum exponent)
    def normalized_integral_exponent(x)
      x.integral_exponent - (precision - x.number_of_digits)
    end

    # Significand normalized to precision digits
    # x == normalized_integral_significand(x) * radix**(normalized_integral_exponent)
    def normalized_integral_significand(x)
      x.integral_significand*(Decimal.int_radix_power(precision - x.number_of_digits))
    end
    
    def to_normalized_int_scale(x)
      [x.sign*normalized_integral_significand(x), normalized_integral_exponent(x)]
    end


    # TO DO:
    # Ruby-style:
    #  ceil floor truncate round
    #  ** power
    # GDAS
    #  quantize, rescale: cannot be done with BigDecimal
    #  power
    #  exp log10 ln
    #  remainder_near
    #  fma: (not meaninful with BigDecimal bogus rounding)
    
    def sqrt(x)
      # ...
    end
   
    # Ruby-style integer division: (x/y).floor
    def div(x,y)
      x.div(y,self)
    end
    # Ruby-style modulo: x - y*div(x,y)
    def modulo(x,y)
      x.modulo(y,self)
    end
    # Ruby-style integer division and modulo: (x/y).floor, x - y*(x/y).floor
    def divmod(x,y)
      x.divmod(y,self)
    end
            
    # General Decimal Arithmetic Specification integer division: (x/y).truncate
    def divide_int(x,y)
      x.divide_int(y,self)
    end
    # General Decimal Arithmetic Specification remainder: x - y*divide_int(x,y)
    def remainder(x,y)
      x.remainder(y,self)
    end
    # General Decimal Arithmetic Specification remainder-near
    #  x - y*round_half_even(x/y)
    def remainder_near(x,y)
      x.remainder_near(y,self)
    end
    # General Decimal Arithmetic Specification integer division and remainder:
    #  (x/y).truncate, x - y*(x/y).truncate
    def divrem(x,y)
      x.divrem(y,self)
    end
              
    
  end
    
  # Context constructor
  def Decimal.Context(options=:default)
    case options
      when :default
        Decimal.context.new
      when Context
        options
      when nil
        Decimal.context
      else
        Decimal::Context.new(options)
    end
  end
  
  # The current context (thread-local).
  def Decimal.context
    Thread.current['FPNum::RB::Decimal.context'] ||= Decimal::Context.new
  end
  
  # Change the current context (thread-local).
  def Decimal.context=(c)
    Thread.current['FPNum::RB::Decimal.context'] = c    
  end
  
  # Defines a scope with a local context. A context can be passed which will be
  # set a the current context for the scope. Changes done to the current context
  # are reversed when the scope is exited.
  def Decimal.local_context(c=nil)
    keep = context.dup
    if c.kind_of?(Hash)
      Decimal.context.assign c
    else  
      Decimal.context = c unless c.nil?    
    end
    result = yield Decimal.context
    Decimal.context = keep
    result
  end
    
  def Decimal.zero(sign=+1)
    Decimal.new([sign, 0, 0])
  end
  def Decimal.infinity(sign=+1)
    Decimal.new([sign, 0, :inf])
  end
  def Decimal.nan()
    Decimal.new([+1, nil, :nan])
  end


  def initialize(*args)    
    context = nil
    if args.size>0 && args.last.instance_of?(Context)
      context ||= args.pop
    elsif args.size>1 && args.last.instance_of?(Hash)
      context ||= args.pop
    elsif args.size==1 && args.last.instance_of?(Hash)
      arg = args.last
      args = [arg[:sign], args[:coefficient], args[:exponent]]
      context ||= Context(arg) # TO DO: remove sign, coeff, exp form arg
    end
    
    context = Decimal.Context(context)
        
    case args.size
    when 3
      @sign, @coeff, @exp = args
      # TO DO: validate
      
    when 1              
      arg = args.first
      case arg
        
      when Decimal
        @sign, @coeff, @exp = arg.split
      when Integer
        if arg>=0
          @sign = +1
          @coeff = arg
        else
          @sign = -1
          @coeff = -arg
        end
        @exp = 0
        
      when Rational
        x, y = Decimal.new(arg.numerator), Decimal.new(arg.denominator)
        @sign, @coeff, @exp = x.divide(y, context).split
      
      when String
        m = _parser(arg)
        return (context.exception ConversionSyntax, "Invalid literal for Decimal: #{arg.inspect}") if m.nil?
        @sign =  (m.sign == '-') ? -1 : +1 
        if m.int || m.onlyfrac
          if m.int
            intpart = m.int
            fracpart = m.frac
          else
            intpart = ''
            fracpart = m.onlyfrac
          end  
          @exp = m.exp.to_i
          if fracpart
            @coeff = (intpart+fracpart).to_i
            @exp -= fracpart.size
          else
            @coeff = intpart.to_i
          end
        else
          if m.diag
            # NaN
            @coeff = (m.diag.nil? || m.diag.empty?) ? nil : m.diag.to_i
            @exp = m.signal ? :snan : :nan
          else
            # Infinity
            @coeff = 0
            @exp = :inf
          end
        end    
      when Array
        @sign, @coeff, @exp = arg
      else
        raise TypeError, "invalid argument #{arg.inspect}"
      end
    else
      raise ArgumentError, "wrong number of arguments (#{args.size} for 1 or 3)"
    end                
  end


  def split
    [@sign, @coeff, @exp]
  end
  
  def special?
    @exp.instance_of?(Symbol)
  end
  
  def nan?
    @exp==:nan || @exp==:snan
  end
  
  def qnan?
    @exp == :nan
  end
  
  def snan?
    @exp == :snan
  end
  
  def infinite?
    @exp == :inf
  end

  def finite?
    !special?
  end
  
  def zero?
    @coeff==0 && !special?
  end
  
  def nonzero?
    special? || @coeff>0
  end


  
  
  def coerce(other)
    case other
      when Decimal,Integer,Rational
        [Decimal(other),self]
      else
        super
    end
  end
  
  def _bin_op(op, meth, other, context=nil)
    case other
      when Decimal,Integer,Rational
        self.send meth, Decimal(other), context
      else
        x, y = other.coerce(self)
        x.send op, y
    end
  end
  private :_bin_op
  
  def -@(context=nil)    
    #(context || Decimal.context).minus(self)
    _neg(context)
  end

  def +@(context=nil)
    #(context || Decimal.context).plus(self)
    _pos(context)
  end

  def +(other, context=nil)
    _bin_op :+, :add, other, context
  end
  
  def -(other, context=nil)
    _bin_op :-, :substract, other, context
  end
  
  def *(other, context=nil)
    _bin_op :*, :multiply, other, context
  end
  
  def /(other, context=nil)
    _bin_op :/, :divide, other, context
  end

  def %(other, context=nil)
    _bin_op :%, :modulo, other, context
  end


  def add(other, context=nil)

    context = Decimal.Context(context)
    
    if self.special? || other.special?
      ans = _check_nans(context,other)
      return ans if ans
      
      if self.infinite?
        if self.sign != other.sign && other.infinite?
          return context.exception(InvalidOperation, '-INF + INF')
        end
        return Decimal(self)
      end
            
      return Decimal(other) if other.infinite?
    end
      
    exp = [self.integral_exponent, other.integral_exponent].min
    negativezero = (context.rounding == ROUND_FLOOR && self.sign != other.sign)
    
    if self.zero? && other.zero?
      sign = [self.sign, other.sign].max
      sign = -1 if negativezero
      ans = Decimal.new([sign, 0, exp])._fix(context)
      return ans
    end
    
    if self.zero?
      exp = [exp, other.integral_exponent - (context.precision - 1)].max # TODO: is it o.i_e - c.p-1 ?
      return other._rescale(exp, context.rounding)._fix(context)
    end
    
    if other.zero?
      exp = [exp, self.integral_exponent - (context.precision - 1)].max  # TODO: is it o.i_e - c.p-1 ?
      return self._rescale(exp, context.rounding)._fix(context)
    end
    
    op1, op2 = Decimal._normalize(self, other, context.precision)

    result_sign = result_coeff = result_exp = nil
    if op1.sign != op2.sign      
      return ans = Decimal.new([negativezero ? -1 : +1, 0, exp])._fix(context) if op1.integral_significand == op2.integral_significand
      op1,op2 = op2,op1 if op1.integral_significand < op2.integral_significand
      result_sign = op1.sign      
      op1,op2 = op1.copy_negate, op2.copy_negate if result_sign < 0 
    elsif op1.sign < 0 
      result_sign = -1
      op1,op2 = op1.copy_negate, op2.copy_negate
    else
      result_sign = +1
    end
      
    #puts "op1=#{op1.inspect} op2=#{op2.inspect}"


    if op2.sign == +1
      result_coeff = op1.integral_significand + op2.integral_significand
    else
      result_coeff = op1.integral_significand - op2.integral_significand
    end
          
    result_exp = op1.integral_exponent
        
    #puts "->#{Decimal([result_sign, result_coeff, result_exp]).inspect}"
        
    return Decimal([result_sign, result_coeff, result_exp])._fix(context)
                    
  end
  
  
  def substract(other, context=nil)
    
    context = Decimal.Context(context)
    
    if self.special? || other.special?
      ans = _check_nans(context,other)
      return ans if ans
    end
    return add(other.copy_negate, context)
  end
  
  
  def multiply(other, context=nil)
    context = Decimal.Context(context)
    resultsign = self.sign * other.sign
    if self.special? || other.special?
      ans = _check_nans(context,other)
      return ans if ans
            
      if self.infinite?
        return context.exception(InvalidOperation,"(+-)INF * 0") if other.zero?
        return Decimal.infinity(resultsign)        
      end                
      if other.infinity?
        return context.exception(InvalidOperation,"0 * (+-)INF") if self.zero?
        return Decimal.infinity(resultsign)        
      end  
    end
    
    resultexp = self.integral_exponent + other.integral_exponent
    
    return Decimal([resultsign, 0, resultexp])._fix(context) if self.zero? || other.zero?                        
    #return Decimal([resultsign, other.integral_significand, resultexp])._fix(context) if self.integral_significand==1
    #return Decimal([resultsign, self.integral_significand, resultexp])._fix(context) if other.integral_significand==1
    
    return Decimal([resultsign, other.integral_significand*self.integral_significand, resultexp])._fix(context)
    
  end
  
  def divide(other, context=nil)
    
    context = Decimal.Context(context)
    resultsign = self.sign * other.sign
    if self.special? || other.special?
      ans = _check_nans(context,other)
      return ans if ans
      if self.infinite?
        return context.exception(InvalidOperation,"(+-)INF/(+-)INF") if other.infinity?
        return Decimal.infinity(resultsign)        
      end                
      if other.infinity?
        context.exception(Clamped,"Division by infinity")
        return Decimal.new([resultsign, 0, context.etiny])        
      end  
    end
    
    if other.zero?
      return context.exception(DivisionUndefined, '0 / 0') if self.zero?
      return context.exception(DivisionByZero, 'x / 0', resultsign)
    end
    
    if self.zero?
      exp = self.integral_exponent - other.integral_exponent
      coeff = 0
    else
      shift = other.number_of_digits - self.number_of_digits + context.precision + 1
      exp = self.integral_exponent - other.integral_exponent - shift
      if shift >= 0
        coeff, remainder = (self.integral_significand*Decimal.int_radix_power(shift)).divmod(other.integral_significand)
      else
        coeff, remainder = self.integral_significand.divmod(other.integral_significand*Decimal.int_radix_power(-shift))
      end        
      if remainder != 0
        coeff += 1 if (coeff%(Decimal.radix/2)) == 0
      else
        ideal_exp = self.integral_exponent - other.integral_exponent
        while (exp < ideal_exp) && ((coeff % Decimal.radix)==0)
          coeff /= 10
          exp += 1
        end        
      end
      
    end
      
    return Decimal([resultsign, coeff, exp])._fix(context)  
      
  end


  
  
  def abs(context=nil)
    if special?
      ans = _check_nans(context)
      return ans if ans
    end        
    sign<0 ? _neg(context) : _pos(context)          
  end

  def plus(context=nil)
    _pos(context)
  end
  
  def minus(context=nil)
    _neg(context)
  end

  def sqrt(context=nil)
    # (context || Decimal.context).sqrt(self)
  end
  
  # General Decimal Arithmetic Specification integer division and remainder:
  #  (x/y).truncate, x - y*(x/y).truncate
  def divrem(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    sign = self.sign * other.sign
    
    if self.infinite?
      if other.infinite?
        ans = context.exception(InvalidOperation, 'divmod(INF,INF)')
        return [ans,ans]
      else
        return [Decimal.infinity(sign), context.exception(InvalidOperation, 'INF % x')]
      end
    end

    if other.zero?
      if self.zero?        
        ans = context.exception(DivisionUndefined, 'divmod(0,0)')  
        return [ans,ans]
      else  
        return [context.exception(DivisionByZero, 'x // 0', sign),
                 context.exception(InvalidOperation, 'x % 0')]
      end
    end
    
    quotient, remainder = self._divide_truncate(other, context)
    return [quotient, remainder._fix(context)]
  end

  # Ruby-style integer division and modulo: (x/y).floor, x - y*(x/y).floor
  def divmod(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    sign = self.sign * other.sign
    
    if self.infinite?
      if other.infinite?
        ans = context.exception(InvalidOperation, 'divmod(INF,INF)')
        return [ans,ans]
      else
        return [Decimal.infinity(sign), context.exception(InvalidOperation, 'INF % x')]
      end
    end

    if other.zero?
      if self.zero?        
        ans = context.exception(DivisionUndefined, 'divmod(0,0)')  
        return [ans,ans]
      else  
        return [context.exception(DivisionByZero, 'x // 0', sign),
                 context.exception(InvalidOperation, 'x % 0')]
      end
    end
    
    quotient, remainder = self._divide_floor(other, context)
    return [quotient, remainder._fix(context)]
  end


  # General Decimal Arithmetic Specification integer division: (x/y).truncate
  def divide_int(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    sign = self.sign * other.sign

    if self.infinite?
      return context.exception(InvalidOperation, 'INF // INF') if other.infinite?
      return Decimal.infinity(sign)
    end

    if other.zero?
      if self.zero?
        return context.exception(DivisionUndefined, '0 // 0')  
      else  
        return context.exception(DivisionByZero, 'x // 0', sign)
      end
    end
    return self._divide_truncate(other, context).first
  end

  # Ruby-style integer division: (x/y).floor
  def div(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    sign = self.sign * other.sign

    if self.infinite?
      return context.exception(InvalidOperation, 'INF // INF') if other.infinite?
      return Decimal.infinity(sign)
    end

    if other.zero?
      if self.zero?
        return context.exception(DivisionUndefined, '0 // 0')  
      else  
        return context.exception(DivisionByZero, 'x // 0', sign)
      end
    end
    return self._divide_floor(other, context).first
  end


  # Ruby-style modulo: x - y*div(x,y)

  def modulo(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    #sign = self.sign * other.sign

    if self.infinite?
      return context.exception(InvalidOperation, 'INF % x')
    elsif other.zero?
      if self.zero?
        return context.exception(DivisionUndefined, '0 % 0')  
      else  
        return context.exception(DivisionByZero, 'x % 0')
      end
    end

    return self._divide_floor(other, context).last._fix(context)
  end

  # General Decimal Arithmetic Specification remainder: x - y*divide_int(x,y)
  def remainder(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    #sign = self.sign * other.sign

    if self.infinite?
      return context.exception(InvalidOperation, 'INF % x')
    elsif other.zero?
      if self.zero?
        return context.exception(DivisionUndefined, '0 % 0')  
      else  
        return context.exception(DivisionByZero, 'x % 0')
      end
    end

    return self._divide_truncate(other, context).last._fix(context)
  end


  # General Decimal Arithmetic Specification remainder-near:
  #  x - y*round_half_even(x/y)
  def remainder_near(other, context=nil)
    context = Decimal.Context(context)

    ans = _check_nans(context,other)
    return [ans,ans] if ans

    #sign = self.sign * other.sign

    if self.infinite?
      return context.exception(InvalidOperation, 'remainder_near(INF,x)')
    elsif other.zero?
      if self.zero?
        return context.exception(DivisionUndefined, 'remainder_near(0,0)')  
      else  
        return context.exception(DivisionByZero, 'remainder_near(x,0)')
      end
    end
    
    if other.infinite?
      return Decimal.new(self)._fix(context)
    end
    
    ideal_exp = [self.integral_exponent, other.integral_exponent].min
    if self.zero?
      return Decimal([self.sign, 0, ideal_exp])._fix(context)
    end 
    
    expdiff = self.adjusted_exponent - other.adjusted_exponent
    if expdiff >= context.precision+1
      return context.exception(DivisionImpossible)
    elsif expdiff <= -2
      return self.rescale(ideal_exp, context.rounding)._fix(context)
    end
    
      self_coeff = self.integral_significand
      other_coeff = other.integral_significand
      de = self.integral_exponent - other.integral_exponent
      if de >= 0
        self_coeff = Decimal.int_mult_radix_power(self_coeff, de)
      else
        other_coeff = Decimal.int_mult_radix_power(other_coeff, -de)
      end
      q, r = self_coeff.divmod(other_coeff)
      if 2*r + (q&1) > other_coeff
        r -= other_coeff
        q += 1
      end
      
      return context.exception(DivisionImpossible) if q >= Decimal.int_radix_power(context.precision)

      sign = self.sign
      if r < 0
        sign = -sign
        r = -r
      end
    
    return Decimal.new([sign, r, ideal_exp])._fix(context)
      
  end
  

  def reduce(context=nil)
    context = Decimal.Context(context)
    if special?
      ans = _check_nans(context)
      return ans if ans
    end        
    dup = _fix(context)
    return dup if dup.infinite?
    
    return Decimal.new([dup.sign, 0, 0]) if dup.zero?
    
    exp_max = context.clamp? ? context.etop : context.emax
    end_d = nd = number_of_digits
    exp = dup.integral_exponent
    dgs = dup.digits
    while dgs[end_d-1]==0 && exp < exp_max
      exp += 1
      end_d -= 1
    end
    return Decimal.new([dup.sign, dup.integral_significand/Decimal.int_radix_power(nd-end_d), exp])
    
  end

  def logb(context=nil)
    (context || Decimal.context).logb(self)
  end

  def scaleb(other, context=nil)
        
    context = Decimal.Context(context)
    other = Decimal(other)
    ans = _check_nans(context, other)
    return ans if ans
    return context.exception(InvalidOperation) if other.integral_exponent != 0
    liminf = -2 * (context.emax + context.precision)
    limsup =  2 * (context.emax + context.precision)
    i = other.to_i
    context.exception(InvalidOperation) if !((liminf <= i) && (i <= limsup))
    return Decimal.new(self) if infinite?
    return Decimal.new(@sign, @coeff, @exp+i)._fix(context)
    
  end


  def to_i
    if special?
      return Decimal.context.exception(InvalidContext) if nan?
    elsif infinite?
      raise OverflowError, "Cannot convert infinity to Integer"
    end
    if @exp >= 0
      return @sign*Decimal.int_mult_radix_power(@coeff,@exp)
    else
      return @sign*Decimal.int_div_radix_power(@coeff,-@exp)      
    end
  end

  def to_s(eng=false,context=nil)
    # (context || Decimal.context).to_string(self)
    sgn = sign<0 ? '-' : ''
    if special?
      if @exp==:inf
        "#{sgn}Infinity"
      elsif @exp==:nan
        "#{sgn}NaN#{coeff}"
      else # exp==:snan
        "#{sgn}sNaN#{coeff}"
      end
    else
      ds = @coeff.to_s
      n_ds = ds.size
      exp = integral_exponent
      leftdigits = exp + n_ds
      if exp<=0 && leftdigits>-6
        dotplace = leftdigits
      elsif !eng
        dotplace = 1
      elsif @coeff==0
        dotplace = (leftdigits+1)%3 - 1
      else
        dotplace = (leftdigits-1)%3 + 1
      end
      
      if dotplace <=0
        intpart = '0'
        fracpart = '.' + '0'*(-dotplace) + ds
      elsif dotplace >= n_ds
        intpart = ds + '0'*(dotplace - n_ds)
        fracpart = ''
      else
        intpart = ds[0...dotplace]
        fracpart = '.' + ds[dotplace..-1]
      end
      
      if leftdigits == dotplace
        e = ''
      else
        context = Decimal.Context(context)
        e = (context.capitals ? 'E' : 'e') + "%+d"%(leftdigits-dotplace)
      end
      
      sgn + intpart + fracpart + e
        
    end
  end    
  
  def inspect
    #"Decimal('#{self}')"
    #debug:
    "Decimal('#{self}') [coeff:#{@coeff.inspect} exp:#{@exp.inspect} s:#{@sign.inspect}]"
  end
  
  def <=>(other)
    case other
      when Decimal,Integer,Rational
        other = Decimal(other)
        if self.special? || other.special?
          if self.nan? || other.nan?
            1
          else
            self.sign <=> other.sigh
          end
        else
          if self.zero?
            if other.zero?
              0
            else
              -other.sign
            end
          elsif other.zero?
            self.sign
          elsif other.sign < self.sign
            -1
          elsif self.sign < other.sign
            1
          else
            self_adjusted = self.adjusted_exponent
            other_adjusted = other.adjusted_exponent
            if self_adjusted == other_adjusted
              self_padded,other_padded = self.integral_significand,other.integral_significand
              d = self.integral_exponent - other.integral_exponent
              if d>0
                self_padded *= Decimal.int_radix_power(d)
              else
                other_padded *= Decimal.int_radix_power(-d)
              end
              (self_padded <=> other_padded)*self.sign
            elsif self_adjusted > other_adjusted
              self.sign
            else
              -self.sign
            end                          
          end
        end
      else
        if defined? other.coerce
          x, y = other.coerce(self)
          x <=> y
        else
          nil
        end
      end
  end
  def ==(other)
    (self<=>other) == 0
  end
  include Comparable

  def hash
    if finite?
      reduce.hash!      
    else
      super
    end      
  end
  def hash!
    super.hash
  end

  # Digits of the significand as an array of integers
  def digits
    @coeff.to_s.split('').map{|d| d.to_i}
  end



  
  # Exponent of the magnitude of the most significant digit of the operand 
  def adjusted_exponent
    if special?
      0
    else
      @exp + number_of_digits - 1
    end
  end
  
  def scientific_exponent
    adjusted_exponent
  end
  # Exponent as though the significand were a fraction (the decimal point before its first digit)
  def fractional_exponent
    scientific_exponent + 1
  end  
    
  # Number of digits in the significand
  def number_of_digits
    # digits.size
    @coeff.to_s.size
  end
  
  # Significand as an integer
  def integral_significand
    @coeff
  end
  
  # Exponent of the significand as an integer
  def integral_exponent
    fractional_exponent - number_of_digits
  end
  
  # +1 / -1
  def sign
    @sign
  end
  
  def to_int_scale
    if special?
      nil
    else
      [@sign*integral_significand, integral_exponent]
    end
  end




  def _neg(context=nil)
    if special?
      ans = _check_nans(context)
      return ans if ans
    end
    if zero?
      ans = copy_abs
    else
      ans = copy_negate
    end
    context = Decimal.Context(context)
    ans._fix(context)
  end
    
  def _pos(context=nil)
    if special?
      ans = _check_nans(context)
      return ans if ans
    end
    if zero?
      ans = copy_abs
    else
      ans = Decimal.new(self)
    end
    context = Decimal.Context(context)
    ans._fix(context)
  end    
    
  def _abs(round=true, context=nil)
    return copy_abs if not round
    
    if special?
      ans = _check_nans(context)
      return ans if ans
    end
    if sign>0
      ans = _neg(context)
    else
      ans = _pos(context)
    end
    ans
  end
    
  def _fix(context)
    if special?
      if nan?
        return _fix_nan(context)
      else
        return Decimal.new(self)
      end
    end
    
    etiny = context.etiny
    etop  = context.etop
    exp = integral_exponent
    if zero?
      exp_max = context.clamp? ? context.emax : etop
      new_exp = [[exp, etiny].max, exp_max].min
      if new_exp!=exp
        context.exception Clamped
        return Decimal.new([sign,0,new_exp])
      else
        return Decimal.new(self)
      end
    end
    
    nd = number_of_digits
    exp_min = nd + @exp - context.precision
    if exp_min > etop
      context.exception Inexact
      context.exception Rounded
      return context.exception(Overflow, 'above Emax', sign)
    end
    
    self_is_subnormal = exp_min < etiny
    
    if self_is_subnormal
      context.exception Subnormal
      exp_min = etiny
    end
    
    if @exp < exp_min
      #puts "_fix(#{self}) rounded; e=#{@exp} em=#{exp_min}"
      context.exception Rounded      
      # dig is the digits number from 0 (MS) to number_of_digits-1 (LS)
      # dg = numberof_digits-dig is from 1 (LS) to number_of_digits (MS)
      dg = exp_min - @exp # dig = number_of_digits + exp - exp_min            
      if dg > number_of_digits # dig<0 
        d = Decimal.new([sign,1,exp_min-1])
        dg = number_of_digits # dig = 0
      else
        d = Decimal.new(self)
      end
      changed = d._round(context.rounding, dg)
      coeff = Decimal.int_div_radix_power(d.integral_significand, dg)
      coeff += 1 if changed==1
      ans = Decimal.new([sign, coeff, exp_min])
      if changed!=0
        context.exception Inexact
        if self_is_subnormal
          context.exception Underflow
          if ans.zero?
            context.exception Clamped
          end
        elsif ans.number_of_digits == context.precision+1
          if ans.integral_exponent< etop
            ans = Decimal.new([ans.sign, Decimal.int_div_radix_power(ans.integral_significand,1), ans.integral_exponent+1])
          else
            ans = context.exception(Overflow, 'above Emax', d.sign)
          end
        end
      end
      return ans
    end
    
    if context.clamp? && exp>etop
      context.exception Clamped
      self_padded = int_mult_radix_power(exp-etop)
      return Decimal.new([sign,self_padded,etop])
    end
    
    return Decimal.new(self)
                                        
  end    

  
  ROUND_ARITHMETIC = true
  
  def _round(rounding, i)
    send("_round_#{rounding}", i)
  end
  
  def _round_down(i)
    if ROUND_ARITHMETIC
      (@coeff % Decimal.int_radix_power(i))==0 ? 0 : -1
    else
      d = @coeff.to_s
      p = d.size - i
      d[p..-1].match(/\A0+\Z/) ? 0 : -1
    end
  end
  def _round_up(i)
    -_round_down(i)
  end
  
  def _round_half_down(i)
    if ROUND_ARITHMETIC
      m = Decimal.int_radix_power(i)
      if (m>1) && ((@coeff%m) == m/2)
        -1
      else
        _round_half_up(i)
      end
    else
      d = @coeff.to_s
      p = d.size - i
      d[p..-1].match(/^5d*$/) ? -1 : _round_half_up(i)
    end      
      
  end
  
  def _round_half_up(i)
    if ROUND_ARITHMETIC
      m = Decimal.int_radix_power(i)
      if (m>1) && ((@coeff%m) >= m/2)
        1
      else
        (@coeff % m)==0 ? 0 : -1
      end
    else
      d = @coeff.to_s
      p = d.size - i
      if '56789'.include?(d[p,1])
        1
      else
        d[p..-1].match(/^0+$/) ? 0 : -1
      end      
    end      
      
  end
  
  def _round_half_even(i)
    if ROUND_ARITHMETIC
      m = Decimal.int_radix_power(i)
      if (m>1) && ((@coeff%m) == m/2 && ((@coeff/m)%2)==0)
        -1
      else
        _round_half_up(i)
      end        
    else
      d = @coeff.to_s
      p = d.size - i
      
      if d[p..-1].match(/\A#{radix/2}0*\Z/) && (p==0 || ((d[p-1,1].to_i%2)==0))
        -1
      else
        _round_half_up(i)
      end
            
    end
  end  
    
    
  def _round_ceiling(i)
    sign<0 ? _round_down(i) : -_round_down(i)    
  end
  def _round_floor(i)
    sign>0 ? _round_down(i) : -_round_down(i)    
  end
  def _round_up05(i)
    if ROUND_ARITHMETIC      
      dg = (@coeff%int_radix_power(i+1))/int_radix_power(i)
    else
      d = @coeff.to_s
      p = d.size - i
      dg = (p>0) ? d[p-1,1].to_i : 0
    end
    if [0,radix/2].include?(dg)
      -_round_down(i)
    else
      _round_down(i)
    end  
  end
      
    # adjust payload of a NaN to the context  
    def _fix_nan(context)      
      payload = @significand

      max_payload_len = context.precision
      max_payload_len -= 1 if context.clamp

      if number_of_digits > max_payload_len
          payload = payload.to_s[-max_payload_len..-1].to_i
          return Decimal([@sign, payload, @exp])
      end
      Decimal(self)
    end

    def _check_nans(context=nil, other=nil)
      self_is_nan = self.nan?
      other_is_nan = other.nil? ? false : other.nan?
      if self.nan? || (other && other.nan?)
        context = Decimal.Context(context)
        return context.exception(InvalidOperation, 'sNan', self) if self.snan?
        return context.exception(InvalidOperation, 'sNan', other) if other.snan?
        return self._fix_nan(context) if self.nan?
        return other._fix_nan(context)
      else
        return nil
      end                
      
    end


  def _rescale(exp,rounding)
    
    
    return Decimal.new(self) if special?
    return Decimal.new([sign, 0, exp]) if zero?    
    return Decimal.new([sign, @coeff*Decimal.int_radix_power(self.integral_exponent - exp), exp]) if self.integral_exponent > exp
    #nd = number_of_digits + self.integral_exponent - exp
    nd = exp - self.integral_exponent
    if number_of_digits < nd 
      slf = Decimal.new([sign, 1, exp-1])
      nd = 0
    else
      slf = Decimal.new(self)
    end
    changed = slf._round(rounding, nd)
    coeff = Decimal.int_div_radix_power(@coeff, nd)
    coeff += 1 if changed==1
    Decimal.new([slf.sign, coeff, exp])
    
  end
  
  def Decimal._normalize(op1, op2, prec=0)
    #puts "N: #{op1.inspect} #{op2.inspect} p=#{prec}"
    if op1.integral_exponent < op2.integral_exponent
      swap = true
      tmp,other = op2,op1
    else
      swap = false
      tmp,other = op1,op2
    end
    tmp_len = tmp.number_of_digits
    other_len = other.number_of_digits
    exp = tmp.integral_exponent + [-1, tmp_len - prec - 2].min
    #puts "exp=#{exp}"
    if other_len+other.integral_exponent-1 < exp      
      other = Decimal.new([other.sign, 1, exp])
      #puts "other = #{other.inspect}"
    end
    tmp = Decimal.new([tmp.sign, int_mult_radix_power(tmp.integral_significand, tmp.integral_exponent-other.integral_exponent), other.integral_exponent])
    #puts "tmp=#{tmp.inspect}"
    return swap ? [other, tmp] : [tmp, other]
  end


  def copy_abs
    Decimal.new([+1,@coeff,@exp])
  end
  
  def copy_negate
    Decimal.new([-@sign,@coeff,@exp])
  end
    
  def copy_sign(other)
    Decimal.new([other.sign, self.integral_significand, self.integral_exponent])
  end




  def _divide_truncate(other, context)
    context = Decimal.Context(context)
    sign = self.sign * other.sign
    if other.infinite?
      ideal_exp = self.integral_exponent
    else
      ideal_exp = [self.integral_exponent, other.integral_exponent].min
    end

    expdiff = self.adjusted_exponent - other.adjusted_exponent
    if self.zero? || other.infinite? || (expdiff <= -2)
      return [Decimal.new([sign, 0, 0]), rescale(ideal_exp, context.rounding)]
    end
    if expdiff <= context.precision
      self_coeff = self.integral_significand
      other_coeff = other.integral_significand
      de = self.integral_exponent - other.integral_exponent
      if de >= 0
        self_coeff = Decimal.int_mult_radix_power(self_coeff, de)
      else
        other_coeff = Decimal.int_mult_radix_power(other_coeff, -de)
      end
      q, r = self_coeff.divmod(other_coeff)
      if q < Decimal.int_radix_power(context.precision)
        return [Decimal([sign, q, 0]),Decimal([self.sign, r, ideal_exp])]
      end
    end
    # Here the quotient is too large to be representable
    ans = context.exception(DivisionImpossible, 'quotient too large in //, % or divmod')
    return [ans, ans]
    
  end
    
  def _divide_floor(other, context)
    context = Decimal.Context(context)
    sign = self.sign * other.sign
    if other.infinite?
      ideal_exp = self.integral_exponent
    else
      ideal_exp = [self.integral_exponent, other.integral_exponent].min
    end

    expdiff = self.adjusted_exponent - other.adjusted_exponent
    if self.zero? || other.infinite? || (expdiff <= -2)
      return [Decimal.new([sign, 0, 0]), rescale(ideal_exp, context.rounding)]
    end
    if expdiff <= context.precision
      self_coeff = self.integral_significand*self.sign
      other_coeff = other.integral_significand*other.sign
      de = self.integral_exponent - other.integral_exponent
      if de >= 0
        self_coeff = Decimal.int_mult_radix_power(self_coeff, de)
      else
        other_coeff = Decimal.int_mult_radix_power(other_coeff, -de)
      end
      q, r = self_coeff.divmod(other_coeff)
      if r<0
        r = -r
        rs = -1
      else
        rs = +1
      end        
      if q<0
        q = -q
        qs = -1
      else
        qs = +1
      end        
      if q < Decimal.int_radix_power(context.precision)
        return [Decimal([qs, q, 0]),Decimal([rs, r, ideal_exp])]
      end
    end
    # Here the quotient is too large to be representable
    ans = context.exception(DivisionImpossible, 'quotient too large in //, % or divmod')
    return [ans, ans]
    
  end
        


  def _parser(txt)
    md = /^\s*([-+])?(?:(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([-+]?\d+))?|Inf(?:inity)?|(s)?NaN(\d*))\s*$/i.match(txt)
    if md
      OpenStruct.new :sign=>md[1], :int=>md[2], :frac=>md[3], :onlyfrac=>md[4], :exp=>md[5], 
                     :signal=>md[6], :diag=>md[7]
    end    
  end

end

# Decimal constructor
def Decimal(*args)
  if args.size==1 && args.first.instance_of?(Decimal)
    args.first
  else
    Decimal.new(*args)
  end
end  
module_function :Decimal

end
end