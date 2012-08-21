! options.f90: Library for command-line options processing.
! version 0.5
! C.N. Gilbreth 2009-2012

! To Do:
!   1. Implement process_input_file()
!   2. Implement functionality for positional arguments
!
! Design notes:
!   1. We require the user to provide default values of all options so that
!      get_option always returns something reasonable/well-defined.
!   2. Setting default values of nopts and nargs in options_t requires the
!      save attribute, but guarantees proper initialization of these variables
!      without any extra action by the user.
!   3. We specify types in function names (e.g. define_option_real) to allow
!      different option types which use the same underlying data type, and to
!      make adding new option types as simple as possible (just copy & edit the
!      code for e.g. reals).

module options
  use, intrinsic :: iso_fortran_env, only: output_unit, error_unit
  implicit none
  private

  ! Can customize these parameters as desired:

  ! Max number of options & positional arguments
  integer, parameter :: maxopts = 16
  integer, parameter :: maxargs = 16
  ! For formatting output
  integer, parameter :: name_column  = 3
  integer, parameter :: descr_column = 30
  integer, parameter :: max_column   = 90
  ! Kind for real options
  integer, parameter :: rk = selected_real_kind(p=15)
  ! Kind for integer options
  integer, parameter :: ik = kind(1)
  ! String lengths
  integer, parameter :: opt_len = 256
  integer, parameter :: descr_len = 2048

  ! ** Option data types *******************************************************

  integer, parameter :: T_NONE=0, T_INTEGER=1, T_LOGICAL=2, T_FLAG=3, T_REAL=4,&
       T_STRING=5

  ! ** Option type *************************************************************

  type opt_t
     character (len=opt_len)   :: name
     character (len=1)         :: abbrev
     character (len=descr_len) :: descr
     logical :: required, found
     integer :: dtype

     ! All types: the value as a string
     character(len=opt_len) :: str

     ! For integer options
     integer(ik) :: ival
     integer(ik) :: imin, imax

     ! For logical options and flags
     logical :: lval

     ! For real options
     real(rk) :: rval
     real(rk) :: rmin, rmax

     ! For string/character options
     character (len=opt_len)   :: cval
  end type opt_t

  ! Predicate:
  ! Defined(opt) :=
  !   Defined(name,abbrev,descr,required,found,dtype)
  !   .and. (dtype == T_INTEGER ==> Defined(ival,imin,imax))
  !   .and. (dtype == T_REAL ==> Defined(rval,rmin,rmax))
  !   .and. (dtype == T_LOGICAL ==> Defined(lval))
  !   .and. (dtype == T_STRING ==> Defined(cval))
  !   .and. (dtype == T_FLAG ==> Defined(lval))
  !
  ! For any intrinsic Fortran type, Defined means that the value has been
  ! explicitly set in the program either to a valid value (either a default
  ! value or an input value).
  !
  ! For names, Defined(name) ==> is_name(name)
  ! Abbreviations: Defined(a) ==> (a == ' ' .or. is_abbrev_char(a)

  ! ** Main options structure **************************************************

  type options_t
     private
     ! Options
     integer :: nopts = 0
     type(opt_t) :: opts(maxopts)
     ! Positional arguments
     integer :: nargs = 0
     character(len=opt_len) :: args(maxargs)
  end type options_t

  ! Invariants:
  ! 1. nopts ≤ maxopts
  ! 2. Defined(opts(i)) ∀ i ∈ {1,...,nopts}
  ! 3. opts(i)%name .ne. opts(j)%name ∀ i,j ∈ {1,...,nopts}
  ! 4. (opts(i)%abbrev .ne. opts(j)%abbrev) .or. opts(i)%abbrev == ' '
  !      ∀ i,j ∈ {1,...,nopts}

  public :: options_t


  ! ** Public interface functions **********************************************

  public :: define_option_integer, define_option_real, define_option_logical, &
       define_option_string, define_flag
  public :: get_option_integer, get_option_real, get_option_logical, &
       get_option_string, get_flag
  public :: print_option, print_options, print_option_values, print_args
  public :: option_found, check_required_options
  public :: process_command_line
  public :: get_arg, get_num_args

  ! ****************************************************************************

contains

  ! ** REAL OPTIONS ********************************************************** !

  subroutine define_option_real(opts,name,default,min,max,abbrev,required,description)
    ! Status: Proved
    ! Defined(opt)
    implicit none
    type(options_t),  target, intent(inout) :: opts
    character(len=*), intent(in) :: name
    real(rk),         intent(in) :: default
    real(rk),         optional, intent(in) :: min, max
    character(len=*), optional, intent(in) :: abbrev
    logical,          optional, intent(in) :: required
    character(len=*), optional, intent(in) :: description

    type(opt_t), pointer :: opt

    opt => new_opt(opts,name,abbrev,required,description)

    opt%dtype = T_REAL
    opt%rval  = default
    opt%rmin  = -huge(1._rk)
    opt%rmax  = huge(1._rk)

    if (present(min)) opt%rmin = min
    if (present(max)) opt%rmax = max
  end subroutine define_option_real


  subroutine get_option_real(opts,name,val)
    ! Status: reviewed
    implicit none
    type(options_t), target, intent(in) :: opts
    character(len=*), intent(in) :: name
    real(rk), intent(out) :: val

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name=name,dtype=T_REAL)
    val = opt%rval
  end subroutine get_option_real


  subroutine set_value_real(opt,valstr,ierr)
    ! Status: proved
    ! Defined(opt) .and. ierr == 0
    !     ==>  IsReal(valstr) .and. Defined(opt%rval) and InBounds(opt%rval)
    implicit none
    type(opt_t), intent(inout) :: opt
    character(len=*), intent(in) :: valstr
    integer, intent(out) :: ierr

    integer :: ios

    ierr = 1
    if (.not. is_real(valstr)) then
       write (error_unit,'(3a)') "Error: parameter ", trim(valstr), " is not a valid real number."
       return
    end if
    read(valstr,*,iostat=ios) opt%rval
    if (ios .ne. 0) then
       write (error_unit,'(3a)') "Error: couldn't convert ", trim(valstr), " to a real number."
       return
    end if
    if (opt%rval < opt%rmin .or. opt%rval > opt%rmax) then
       write (error_unit,'(3a)') 'Error: value for option "', trim(opt%name), '" out of range.'
       write (error_unit,'(3(a,es15.8))') "Value: ", opt%rval, ", min: ", opt%rmin, ", max: ", opt%rmax
       return
    end if
    ierr = 0
  end subroutine set_value_real


  subroutine print_value_real(opt,unit)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(in) :: opt
    integer, optional, intent(in) :: unit

    integer :: m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit
    write (m_unit,'(2a,t30,es17.9e3)') trim(opt%name), ': ', opt%rval
  end subroutine print_value_real


  ! ** INTEGER OPTIONS ******************************************************* !


  subroutine define_option_integer(opts,name,default,min,max,abbrev,required,description)
    ! Status: reviewed
    implicit none
    type(options_t), target,  intent(inout) :: opts
    character(len=*), intent(in) :: name
    integer(ik),      intent(in) :: default
    integer(ik),      optional, intent(in) :: min, max
    character(len=*), optional, intent(in) :: abbrev
    logical,          optional, intent(in) :: required
    character(len=*), optional, intent(in) :: description

    type(opt_t), pointer :: opt

    opt => new_opt(opts,name,abbrev,required,description)

    opt%dtype  = T_INTEGER
    opt%ival   = default
    opt%imin   = -huge(1_ik)
    opt%imax   = huge(1_ik)

    if (present(min)) opt%imin = min
    if (present(max)) opt%imax = max
  end subroutine define_option_integer


  subroutine get_option_integer(opts,name,val)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(in) :: opts
    character(len=*), intent(in)  :: name
    integer(ik),      intent(out) :: val

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name=name,dtype=T_INTEGER)
    val = opt%ival
  end subroutine get_option_integer


  subroutine set_value_integer(opt,valstr,ierr)
    ! Status: Proved
    ! Defined(opt) .and. ierr == 0
    !     ==>  Defined(opt%ival) .and. IsInteger(valstr) .and. InBounds(opt%ival)
    implicit none
    type(opt_t), intent(inout) :: opt
    character(len=*), intent(in) :: valstr
    integer, intent(out) :: ierr

    integer :: ios

    ierr = 1
    if (.not. is_integer(valstr)) then
       write (error_unit,'(3a)') "Error: parameter ", trim(valstr), " is not a valid integer."
       ! ierr == 1 .and. .not.  is_integer(valstr)
       return
    end if
    read(valstr,*,iostat=ios) opt%ival
    if (ios .ne. 0) then
       write (error_unit,'(3a)') "Error: couldn't convert ", trim(valstr), " to an integer&
            & (may be too large)."
       ! ierr == 1 .and. .not. valid(opt%ival)
       return
    end if
    ! valid(opt%ival) .and. is_integer(valstr)
    if (opt%ival < opt%imin .or. opt%ival > opt%imax) then
       write (error_unit,'(3a)') 'Error: value for option "', trim(opt%name), '" out of range.'
       write (error_unit,'(3(a,i0))') "Value: ", opt%ival, ", min: ", opt%imin, ", max: ", opt%imax
       ! ierr == 1 .and. valid(opt%ival) .and. is_integer(valstr) .and. OutOfBounds(opts%ival)
       return
    end if
    ! opt%ival >= opt%imin .and. opt%ival <= opt%imax
    ! valid(opt%ival) .and. is_integer(valstr) .and. InBounds(opt%ival)
    ierr = 0
  end subroutine set_value_integer


  subroutine print_value_integer(opt,unit)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(in) :: opt
    integer, optional, intent(in) :: unit

    integer :: m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit
    write (m_unit,'(2a,t30,i0)') trim(opt%name), ': ', opt%ival
  end subroutine print_value_integer


  ! ** LOGICAL OPTIONS ******************************************************* !


  subroutine define_option_logical(opts,name,default,abbrev,required,description)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(inout) :: opts
    character(len=*), intent(in) :: name
    logical,          intent(in) :: default
    character(len=*), optional, intent(in) :: abbrev
    logical,          optional, intent(in) :: required
    character(len=*), optional, intent(in) :: description

    type(opt_t), pointer :: opt

    opt => new_opt(opts,name,abbrev,required,description)

    opt%dtype = T_LOGICAL
    opt%lval  = default
  end subroutine define_option_logical


  subroutine get_option_logical(opts,name,val)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(in) :: opts
    character(len=*), intent(in)  :: name
    logical,          intent(out) :: val

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name=name,dtype=T_LOGICAL)
    val = opt%lval
  end subroutine get_option_logical


  subroutine set_value_logical(opt,valstr,ierr)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(inout) :: opt
    character(len=*), intent(in) :: valstr
    integer, intent(out) :: ierr

    integer :: ios

    ierr = 1
    if (.not. is_logical(valstr)) then
       write (error_unit,'(3a)') "Error: parameter ", trim(valstr), " is not a valid logical value."
       return
    end if
    read(valstr,*,iostat=ios) opt%lval
    if (ios .ne. 0) then
       write (error_unit,'(3a)') "Error: couldn't convert ", trim(valstr), " to a logical value."
       return
    end if
    ierr = 0
  end subroutine set_value_logical


  subroutine print_value_logical(opt,unit)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(in) :: opt
    integer, optional, intent(in) :: unit

    integer :: m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit
    write (m_unit,'(2a,t30,l1)') trim(opt%name), ': ', opt%lval
  end subroutine print_value_logical


  ! ** STRING OPTIONS ******************************************************** !


  subroutine define_option_string(opts,name,default,abbrev,required,description)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(inout) :: opts
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: default
    character(len=*), optional, intent(in) :: abbrev
    logical,          optional, intent(in) :: required
    character(len=*), optional, intent(in) :: description

    type(opt_t), pointer :: opt

    opt => new_opt(opts,name,abbrev,required,description)

    opt%dtype = T_STRING
    opt%cval  = default
  end subroutine define_option_string


  subroutine get_option_string(opts,name,val)
    ! Status: reviewed
    implicit none
    type(options_t),   target, intent(in) :: opts
    character(len=*), intent(in)  :: name
    character(len=*), intent(out) :: val

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name=name,dtype=T_STRING)
    if (len_trim(opt%cval) > len(val)) then
       write (error_unit,'(a)') "get_option_string: string too long. &
            &Need to supply more storage space when calling this routine."
       stop
    end if
    val = opt%cval
  end subroutine get_option_string


  subroutine set_value_string(opt,valstr,ierr)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(inout) :: opt
    character(len=*), intent(in) :: valstr
    integer, intent(out) :: ierr

    ierr = 1
    if (len_trim(valstr) > len(opt%cval)) then
       write (error_unit,'(a)') "set_value_string: value too long. Need to &
            &increase parameter opt_len in options.f90."
       return
    end if
    opt%cval = valstr
    ierr = 0
  end subroutine set_value_string


  subroutine print_value_string(opt,unit)
    ! Status: reviewed
    implicit none
    type(opt_t), intent(in) :: opt
    integer, optional, intent(in) :: unit

    integer :: m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit
    write (m_unit,'(2a,t30,a)') trim(opt%name), ': ', trim(opt%cval)
  end subroutine print_value_string


  ! ** FLAGS ***************************************************************** !


  subroutine define_flag(opts,name,abbrev,description)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(inout) :: opts
    character(len=*), intent(in) :: name
    character(len=*), optional, intent(in) :: abbrev
    character(len=*), optional, intent(in) :: description

    type(opt_t), pointer :: opt

    opt => new_opt(opts,name,abbrev,required=.false.,description=description)

    opt%dtype = T_FLAG
    opt%lval  = .false.
  end subroutine define_flag


  subroutine get_flag(opts,name,val)
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(in) :: opts
    character(len=*), intent(in)  :: name
    logical,          intent(out) :: val

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name=name,dtype=T_FLAG)
    val = opt%lval
  end subroutine get_flag



  ! ** ROUTINES WHICH CALL THE SPECIALIZED ROUTINES ABOVE ******************** !


  subroutine print_option_values(opts,unit)
    ! Status: proved, assuming unit is valid for writing.
    implicit none
    type(options_t), target, intent(in) :: opts
    integer, optional, intent(in) :: unit

    type(opt_t), pointer :: opt
    integer :: iopt, m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit
    write (m_unit,'(a)') "Option values: "

    do iopt=1,opts%nopts
       opt => opts%opts(iopt)
       select case (opt%dtype)
       case (T_INTEGER)
          call print_value_integer(opt,unit)
       case (T_REAL)
          call print_value_real(opt,unit)
       case (T_LOGICAL)
          call print_value_logical(opt,unit)
       case (T_FLAG)
          call print_value_logical(opt,unit)
       case (T_STRING)
          call print_value_string(opt,unit)
       case default
          stop "Error in print_option_values(): invalid type"
       end select
    end do
  end subroutine print_option_values


  subroutine set_opt(opt,valstr,ierr)
    ! Set the value of an option, given a string representing the value.
    ! If the option has already been set, error out. Otherwise, mark the option
    ! as having been found and set opt%str.
    ! Note: opt must be a properly initialized/defined option structure.
    ! Status: reviewed
    ! ierr .ne. 0 ==> IsValid(valstr,opt)
    implicit none
    type(opt_t),      intent(inout) :: opt
    character(len=*), intent(in) :: valstr
    integer, intent(out) :: ierr

    ierr = 1
    if (opt%found) then
       write (error_unit,'(3a)') 'Error: tried to set option "', trim(opt%name), '" twice.'
       return
    else
       opt%found = .true.
    end if

    select case (opt%dtype)
    case (T_INTEGER)
       call set_value_integer(opt,valstr,ierr)
    case (T_REAL)
       call set_value_real(opt,valstr,ierr)
    case (T_LOGICAL)
       call set_value_logical(opt,valstr,ierr)
    case (T_FLAG)
       call set_value_logical(opt,valstr,ierr)
    case (T_STRING)
       call set_value_string(opt,valstr,ierr)
    case default
          stop "Error in set_opt(): invalid type"
    end select
    opt%str = valstr
  end subroutine set_opt


  ! ** GENERAL ROUTINES ********************************************************


  logical function is_logical(str)
    ! Return .true. if str represents a logical value.
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str

    character(len=len(str)) :: ustr

    ustr = upcase(str)
    is_logical = ustr == 'T' .or. ustr == 'F' .or. ustr == '.TRUE.' &
         .or. ustr == '.FALSE.' .or. ustr == 'TRUE' .or. ustr == 'FALSE'
  end function is_logical


  logical function is_integer(str)
    ! Return .true. if str represents an integer, i.e. has the form
    !   [+-]i_1...i_{n_i}
    ! where n_i > 0 and i_k are digits (0-9).
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str

    integer :: lt,pm,ni

    lt = len_trim(str)
    is_integer = .false.
    pm = count_leading_set(str,"+-")
    if (pm > 1) return
    if (pm == lt) return
    ni = count_leading_set(str(pm+1:lt),'0123456789')
    if (pm + ni .ne. lt) return
    is_integer = .true.
  end function is_integer


  logical function is_real(str)
    ! Return .true. if str represents a real number, i.e. has one of the forms
    !  (i)   [+-]i_1...i_{n_i}  where n_i > 0
    !  (ii)  [+-]i_1...i_{n_i}.d_1...d_{n_d} where n_i > 0 or n_d > 0
    !  (iii) [+-]i_1...i_{n_i}(E|e)[+-]e_1...e_{n_e} where n_i > 0, n_e > 0
    !  (iv)  [+-]i_1...i_ni.d_1...d_{n_d}(E|e)[+-]e_1...e_{n_e}
    !         where (n_i > 0 or n_d > 0) and n_e > 0.
    ! Here i_k, d_k and e_k are digits (0-9).
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str

    integer :: lt,pm,ni,dot,nd,ee,pm2,ne

    lt = len_trim(str)

    ! Notes:
    !   1. if x = count_leading_set(str(lb+1:ub),set) and ub > lb then it's
    !      guaranteed that lb + x <= ub. Therefore either lb + x < ub or
    !      lb + x == ub.
    !   2. if x = count_leading_set(str(lb+1:ub),set), then str(lb+1:lb+x) ∈ set.

    is_real = .false.
    pm = count_leading_set(str,"+-")
    if (pm > 1) return
    if (pm == lt) return
    ! pm < lt, str(1:pm) ∈ '+-'
    ni = count_leading_set(str(pm+1:lt),'0123456789')
    ! pm+ni ≤ lt, str(pm+1:pm+ni) ∈ '0123456789'
    if (pm + ni == lt) then
       if (ni > 0) is_real = .true. ! Case (i)
       return
    end if
    ! pm+ni < lt
    dot = count_leading_set(str(pm+ni+1:lt),'.')
    ! pm+ni+dot ≤ lt, str(pm+ni+1:pm+ni+dot) ∈ '.'
    if (dot .gt. 1) return
    if (pm+ni+dot == lt) then
       if (ni > 0) is_real = .true. ! Case (ii), n_d = 0
       return
    end if
    ! pm+ni+dot < lt
    nd = count_leading_set(str(pm+ni+dot+1:lt),'0123456789')
    if (ni == 0 .and. nd == 0) return
    ! pm+ni+dot+nd ≤ lt, str(pm+ni+dot+1:pm+ni+dot+nd) ∈ '0123456789', (ni > 0 or nd > 0)
    if (pm+ni+dot+nd == lt) then
       is_real = .true. ! Case (ii)
       return
    end if
    ! etc.
    ee = count_leading_set(str(pm+ni+dot+nd+1:lt),'Ee')
    if (ee .ne. 1) return
    if (pm+ni+dot+nd+ee == lt) return
    pm2 = count_leading_set(str(pm+ni+dot+nd+ee+1:lt),'+-')
    if (pm+ni+dot+nd+ee+pm2 == lt) return
    ne = count_leading_set(str(pm+ni+dot+nd+ee+pm2+1:lt),'0123456789')
    if (ne == 0) return
    if (pm+ni+dot+nd+ee+pm2+ne .ne. lt) return
    is_real = .true. ! Case (iii) or (iv)
  end function is_real


  function option_found(opts,name)
    ! Status: proved
    implicit none
    type(options_t), target,  intent(in) :: opts
    character(len=*), intent(in) :: name
    logical :: option_found

    type(opt_t), pointer :: opt

    opt => find_opt(opts,name)
    option_found = opt%found
  end function option_found


  function new_opt(opts,name,abbrev,required,description) result(opt)
    ! Allocate and append a new option to the end of the options list, and
    ! initialize the generic fields which apply to all data types.
    ! On exit: Defined(name,abbrev,descr,required,found)
    ! Status: proved
    implicit none
    type(options_t), target, intent(inout) :: opts
    character(len=*), intent(in) :: name
    character(len=*), optional, intent(in) :: abbrev
    logical,          optional, intent(in) :: required
    character(len=*), optional, intent(in) :: description
    ! Return value
    type(opt_t), pointer :: opt

    integer :: iopt

    if (len(name) == 0) stop "Error: empty name for option."
    if (.not. is_name(name)) then
       write (error_unit,*) "Error: invalid option name: ", trim(name)
       stop
    end if
    ! is_name(name)
    if (present(abbrev)) then
       if (.not. (len(abbrev) == 1 .and. is_abbrev_char(abbrev))) then
          write (error_unit,*) "Error: invalid option abbreviation: '", abbrev, "'"
          stop
       end if
    end if
    ! present(abbrev) ==> is_abbrev_char(abbrev)

    do iopt=1,opts%nopts
       call check_name(opts%opts(iopt),name,abbrev)
    end do
    ! name .ne. opt(i)%name for i=1,..,opts%nopts
    opts%nopts = opts%nopts + 1
    if (opts%nopts > maxopts) stop "Error: Need to increase maxopts parameter in options.f90."

    opt => opts%opts(opts%nopts)
    ! Initialize generic fields
    opt%name = name
    opt%abbrev = ' '
    opt%descr = ''
    opt%required = .false.
    opt%found = .false.
    opt%dtype = T_NONE
    if (present(abbrev)) opt%abbrev = abbrev
    if (present(description)) opt%descr = description
    if (present(required)) opt%required = required
    ! Defined(name,abbrev,descr,required,found)
  end function new_opt


  subroutine print_options(opts,unit)
    ! Status: ok
    implicit none
    type(options_t), target, intent(in) :: opts
    integer, optional, intent(in) :: unit

    integer :: m_unit, iopt
    type(opt_t), pointer :: opt

    m_unit = output_unit
    if (present(unit)) m_unit = unit

    write (m_unit,'(a)') 'Options: '
    if (opts%nopts > 0) then
       do iopt=1,opts%nopts
          opt => opts%opts(iopt)
          call print_option(opts,opt%name,unit)
       end do
    end if
  end subroutine print_options


  subroutine print_option(opts,name,unit)
    implicit none
    type(options_t), pointer, intent(in) :: opts
    character(len=*),  intent(in) :: name
    integer, optional, intent(in) :: unit

    integer, parameter :: format_buf_size = 4*descr_len + 2*opt_len
    character(len=format_buf_size) :: buf
    character(2*opt_len) :: synopsis
    type(opt_t), pointer :: opt
    integer :: m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit

    opt => find_opt(opts,name)
    if (opt%dtype == T_FLAG) then
       call format_flag_synopsis(synopsis,opt%name,opt%abbrev)
    else
       call format_val_synposis(synopsis,opt%name,opt%abbrev)
    end if
    call format_opt(buf,synopsis,opt%descr)
    write (m_unit,'(a)',advance='no') trim(buf)
  end subroutine print_option


  subroutine format_val_synposis(buf,name,abbrev)
    ! Status: ok
    implicit none
    character(len=*), intent(out) :: buf
    character(len=*), intent(in) :: name, abbrev

    if (abbrev == ' ') then
       if (2*len_trim(name) + 3 > len(buf)) then
          write (error_unit,'(a)') "Error in format_val_synopsis: need to increase buffer size"
          stop
       end if
       buf = "--" // trim(name) // "=" // upcase(trim(name))
    else
       if (3*len_trim(name) + len_trim(abbrev) + 7 > len(buf)) then
          write (error_unit,'(a)') "Error in format_val_synopsis: need to increase buffer size"
          stop
       end if
       buf = "-" // trim(abbrev) // " " // upcase(trim(name)) &
            // ", " // "--" // trim(name) // "=" // &
            upcase(trim(name))
    end if
  end subroutine format_val_synposis


  subroutine format_flag_synopsis(buf,name,abbrev)
    ! Status: ok
    implicit none
    character(len=*) :: buf
    character(len=*), intent(in) :: name, abbrev

    if (abbrev == ' ') then
       if (len_trim(name) + 2 > len(buf)) then
          write (error_unit,'(a)') "Error in format_flag_synopsis: need to increase buffer size"
          stop
       end if
       buf = "--" // trim(name)
    else
       if (len_trim(name) + len_trim(abbrev) + 5 > len(buf)) then
          write (error_unit,'(a)') "Error in format_flag_synopsis: need to increase buffer size"
          stop
       end if
       buf = "-" // trim(abbrev) &
            // ", " // "--" // trim(name)
    end if
  end subroutine format_flag_synopsis


  function upcase(string) result(upper)
    ! From http://www.star.le.ac.uk/~cgp/fortran.html
    ! Status: reviewed
    character(len=*), intent(in) :: string
    character(len=len(string)) :: upper

    integer :: j

    do j=1,len(string)
       if(string(j:j) >= "a" .and. string(j:j) <= "z") then
          upper(j:j) = achar(iachar(string(j:j)) - 32)
       else
          upper(j:j) = string(j:j)
       end if
    end do
  end function upcase


  function is_name_char(c)
    ! This function determines which characters are allowed in option names.
    ! At minimum, must exclude quotation marks and '='.
    ! Status: reviewed
    implicit none
    character(len=1), intent(in) :: c
    logical :: is_name_char

    integer :: ic

    ic = iachar(c)
    ! Allow all ascii characters except non-printing characters, quotation
    ! marks, space, '!', '#', '=' and '$'
    is_name_char = (ic >= 37 .and. ic <= 38) .or. (ic >= 40 .and. ic <= 60) .or. &
         (ic >= 62 .and. ic <= 95) .or. (ic >= 97 .and. ic <= 126)
    ! TODO: Allow extended ascii?
  end function is_name_char


  function is_name(str)
    ! Names must be nonempty and consist only of name characters.
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str
    logical :: is_name

    integer :: i

    if (len_trim(str) .eq. 0) then
       is_name = .false.
       return
    end if
    is_name = .true.
    do i=1,len_trim(str)
       is_name = is_name .and. is_name_char(str(i:i))
    end do
  end function is_name


  function is_abbrev_char(c)
    ! This function determines which characters are allowed as abbreviations.
    ! Status: reviewed
    implicit none
    character(len=1), intent(in) :: c
    logical :: is_abbrev_char

    ! Allow all name characters except numbers and '.', '-' and '+' (these must
    ! be excluded to allow numeric arguments)
    is_abbrev_char = is_name_char(c) .and. (c < '0' .or. c > '9') .and. c .ne. '.' &
         .and. c .ne. '+' .and. c .ne. '-'
  end function is_abbrev_char


  subroutine format_opt(buf,name,descr)
    ! Format the name/synopsis and description of an option in a readable
    ! format, inserting line breaks in the description as necessary.
    implicit none
    character(len=*), intent(out) :: buf
    character(len=*), intent(in) :: name, descr

    integer :: bufidx, last_blank_didx, last_blank_bufidx, col, didx

    !--<name>-------------------<description...>
    !---------------------------<description cont...>
    ! or
    !--<..........name............>
    !---------------------------<description...>
    !---------------------------<description cont...>

    ! Write <name> and advance to the description column, on the next line if
    ! necessary
    if (name_column + len_trim(name) + 1 + descr_column > len(buf)) then
       write (error_unit,'(a)') "format_opt: need to increase format_buf_size in options.f90."
       stop
    end if
    buf = ' '
    buf(name_column:) = trim(name)
    bufidx = name_column + len_trim(name)
    if (bufidx >= descr_column) then
       buf(bufidx:bufidx) = NEW_LINE('a')
       bufidx = bufidx + descr_column
    else
       bufidx = descr_column
    end if
    col = descr_column

    ! Write <description>, wrapping lines as necessary. Notes:
    ! 1. Each non-blank character is printed exactly once
    ! 2. Line wrapping occurs at spaces if possible
    ! 3. Newlines are honored
    ! 4. All characters are printed between col=descr_column and max_column,
    !    inclusive
    didx = 1
    last_blank_didx = 0
    do while (didx <= len_trim(descr) .and. bufidx <= len(buf))
       ! descr(didx:didx): Next charcter to print
       ! descr_column <= col <= max_column + 1
       ! last_blank_didx == 0 .or. last_blank_didx >= beginning_of_line
       ! last_blank_didx == 0 .or. descr(last_blank_didx) == ' '
       ! last_blank_didx == 0 .or. descr(last_blank_bufidx) == ' '
       if (descr(didx:didx) .ne. new_line('a')) then
          if (descr(didx:didx) == ' ') then
             last_blank_didx = didx
             last_blank_bufidx = bufidx
          end if
          if (col <= max_column) then
             ! place character
             buf(bufidx:bufidx) = descr(didx:didx)
             didx = didx + 1
             bufidx = bufidx + 1
             col = col + 1
          else ! col > max_column
             ! Wrap line:
             if (last_blank_didx > 0) then
                ! Back up to last blank
                buf(last_blank_bufidx:bufidx) = ' '
                bufidx = last_blank_bufidx
                didx = last_blank_didx+1
             else
                ! No blanks: back up one and hyphenate
                didx = didx - 1
                buf(bufidx-1:bufidx-1) = '-'
             end if
             go to 100
          end if
       else ! descr(didx:didx) .eq. new_line('a')
          didx = didx + 1
          go to 100
       end if
       cycle
       ! Linebreak
100    buf(bufidx:bufidx) = new_line('a')
       bufidx = bufidx + descr_column
       last_blank_didx = 0
       col = descr_column
    end do

    if (bufidx > len(buf)) then
       write (error_unit,'(a)') "format_opt: need to increase format_buf_size in options.f90."
       stop
    end if
    buf(bufidx:bufidx) = new_line('a')
  end subroutine format_opt


  subroutine print_args(opts,unit)
    ! Status: reviewed
    implicit none
    type(options_t), target, intent(in) :: opts
    integer, optional, intent(in) :: unit

    integer :: iarg, m_unit

    m_unit = output_unit
    if (present(unit)) m_unit = unit

    write (m_unit,'(a)') 'Arguments: '
    do iarg=1,opts%nargs
       write (m_unit,'(a)') trim(opts%args(iarg))
    end do
  end subroutine print_args


  function find_opt(opts,name,abbrev,dtype,assert) result(opt)
    ! Find the struct for an existing option by either name or abbreviation.
    !
    ! 1. If dtype is present, will also assert that the datatype is the same as
    !    that passed in.
    ! 2. By default, program will terminate if the option can't be found. If
    !    assert is present and .false., the function will instead return a null
    !    pointer.
    ! Status: Reviewed
    ! Show: associated(opt) ==> Defined(opt)
    implicit none
    type(options_t),  target, intent(in) :: opts
    character(len=*), optional, intent(in) :: name
    character(len=1), optional, intent(in) :: abbrev
    integer,          optional, intent(in) :: dtype
    logical,          optional, intent(in) :: assert

    type(opt_t), pointer :: opt
    integer :: iopt
    logical :: m_assert, found

    if (.not. present(name) .and. .not. present(abbrev)) then
       stop "find_opt(): must be called with either name or abbrev."
    else if (present(name) .and. present(abbrev)) then
       stop "find_opt(): should not be called with both name and abbrev."
    end if
    if (present(assert)) then
       m_assert = assert
    else
       m_assert = .true.
    end if

    found = .false.
    do iopt=1,opts%nopts
       opt => opts%opts(iopt)
       if (present(name)) then
          if (opt%name == name) found = .true.
       else if (present(abbrev)) then
          if (opt%abbrev == abbrev) found = .true.
       end if
       if (found .and. present(dtype)) then
          if (dtype .ne. opt%dtype) then
             write (error_unit,'(a,a)') "find_opt(): Datatype doesn't match for option: ", trim(name)
             stop
          end if
       end if
       if (found) return
    end do

    nullify(opt)
    if (m_assert) then
       if (present(name)) then
          write (error_unit,'(a,a)') "find_opt(): Option doesn't exist: ", trim(name)
          stop
       else if (present(abbrev)) then
          write (error_unit,'(a,a)') "find_opt(): Option doesn't exist: ", trim(abbrev)
          stop
       end if
    end if
  end function find_opt


  subroutine store_arg(opts,str)
    ! Status: proved
    implicit none
    type(options_t), target, intent(inout) :: opts
    character(len=*), intent(in) :: str

    if (opts%nargs == maxargs) stop "Error: need to increase maxargs in options.f90"
    opts%nargs = opts%nargs + 1
    opts%args(opts%nargs) = str
  end subroutine store_arg


  subroutine getarg_check(iarg,buf,status)
    ! Status: Proved
    ! status == 0 ==> HasValue(buf)
    implicit none
    integer, intent(in) :: iarg
    character(len=*), intent(out) :: buf
    integer, intent(out) :: status

    integer :: l

    if (iarg > command_argument_count()) stop "Error in getarg_check"
    buf = ''
    call get_command_argument(iarg,buf,status=status,length=l)
    if (status .ne. 0) then
       ! If the value was truncated or the retrieval fails, status .ne. 0.
       ! Otherwise status == 0.
       write (error_unit,'(a,i0,a,i0)') "Error retrieving command argument ", &
            iarg, " status: ", status
       if (l > len(buf)) then
          write (error_unit,'(a,i0,a)') "Error: command argument ", iarg, &
               " too long. May need to increase opt_len in options.f90."
       end if
       return
    end if
  end subroutine getarg_check


  subroutine process_command_line(opts,ierr)
    ! Process the command-line arguments for the program, detecting options
    ! passed and storing their values in the options structure.
    ! If the command-line arguments are invalid (options which don't exist,
    ! etc.), then ierr .ne. 0 is returned.
    ! If an internal buffer is too short, a message is printed and the program
    ! stops.
    ! If the command-line arguments are processed succesfully, ierr=0 is
    ! returned.
    !
    ! The command line has the form
    !
    ! <program_name> <term1> ... <termN>
    !
    ! Where <term> is
    !
    !  (1)  -<f1><f2>...<fN>
    !         where each <fi> is a 1-character abbreviation for a flag
    !  (2)  -<f1><f2>...<fN><opt> <value>
    !         where <opt> is an option abbreviation, and <value> is the next term
    !  (3)  --<flag_name>
    !  (4)  --<flag_name>=<value>
    !  (5)  --<opt_name> <value>
    !         where <value> is the next term
    !  (6)  --<opt_name>=<value>
    !  (7)  -- (double dashes)
    !       If this appears by itself, all subsequent terms are considered
    !       arguments.
    !  (8)  <numeric>, stored as an argument. E.g. -10, 1.23, -.23, 1E10, +0.34
    !  (9)  term which does not begin with a dash (stored as an argument)
    !  (10) - (A single dash by itself is allowed as an argument)
    !
    ! If a term begins with - or -- but doesn't fall into one of the above
    ! categories, it is considered an error, and ierr .ne. 0 is returned.
    ! Status: reviewed
    implicit none
    type(options_t),  target, intent(inout) :: opts
    integer, intent(out) :: ierr

    type(opt_t), pointer :: opt
    character(len=opt_len) :: buf, name, val
    character(len=1) :: eqlc, a
    integer :: iarg, max, j

    max = command_argument_count()

    buf = ''
    iarg = 0
    do while (iarg < max)
       iarg = iarg + 1
       call getarg_check(iarg,buf,ierr)
       if (ierr .ne. 0) return
       if (buf(1:1) == '-' .and. is_abbrev_char(buf(2:2))) then
          ! Short options: Case (1) or (2)
          do j=2,len_trim(buf)
             ! Find the option struct
             a = buf(j:j)
             opt => find_opt(opts,abbrev=a,assert=.false.)
             if (.not. associated(opt)) then
                write (error_unit,'(3a)') 'Error: unknown option: "-', buf(j:j), '"'
                ierr = 1
                return
             end if
             ! associated(opt) => Defined(opt)
             ! Get the option value
             if (opt%dtype == T_FLAG) then
                ! Flags: -<abbrev>, no value allowed
                val = ".true."
                ! IsFlag(opt) .and. HasValue(val)
             else
                ! Non-flag options: -<abbrev> <value>
                iarg = iarg + 1
                if (j .ne. len_trim(buf) .or. iarg > max) then
                   write (error_unit,'(3a)') 'Error: Option "-', buf(j:j), '" requires an argument.'
                   ierr = 1
                   return
                end if
                ! j == lt .and. iarg <= max
                call getarg_check(iarg,val,ierr)
                if (ierr .ne. 0) return
                ! ierr .eq. 0 => HasValue(val)
                ! j == len_trim(buf) .and. HasValue(val)
             end if
             ! HasValue(val) .and. (IsFlag(opt) .or. (j == len_trim(buf))) .and. Defined(opt)
             ! Set the option value
             call set_opt(opt,val,ierr)
             if (ierr .ne. 0) return
             ! IsValid(val,opt)
          end do
       else if (buf(1:2) == '--' .and. is_name_char(buf(3:3))) then
          ! Long options
          call parse_long_option(buf,name,eqlc,val,ierr)
          if (ierr .ne. 0) then
             write (error_unit,'(2a)') 'Error: invalid option string "', trim(buf), '"'
             return
          end if
          ! IsNameString(name) .and. eqlc ∈ " =" .and. (eqlc == '=' ==> HasValue(val))
          ! Find option
          opt => find_opt(opts,name=name,assert=.false.)
          if (.not. associated(opt)) then
             write (error_unit,'(3a)') 'Error: unknown option: "--', trim(name), '"'
             ierr = 1
             return
          end if
          ! Defined(opt)
          ! Get the option value
          if (opt%dtype == T_FLAG) then
             ! IsFlag(opt)
             if (eqlc .eq. ' ') then
                ! Case (3) --<flag_name>
                val = '.true.'
             else
                ! eqlc == '=', so Defined(val)
                ! Case (4) --<flag_name>=<value>
                ! (val is already set, do nothing)
             end if
             ! Defined(val)
          else
             if (eqlc == ' ') then
                ! Case (5) --<opt_name> <value>
                iarg = iarg + 1
                if (iarg > max) then
                   write (error_unit,'(3a)') 'Error: option "--', trim(name), '" requires an argument.'
                   ierr = 1
                   return
                end if
                call getarg_check(iarg,val,ierr)
                if (ierr .ne. 0) return
                ! Defined(val)
             else
                ! eqlc == '='. so Defined(val)
                ! Case (6) --<opt_name>=<value>
                ! (val is already set, do nothing)
             end if
             ! Defined(val)
          end if
          ! Defined(opt) .and. Defined(val)
          ! Set the option value
          call set_opt(opt,val,ierr)
          if (ierr .ne. 0) return
          ! IsValid(val,opt) .and. ValueSet(val,opt)
       else if (buf == "--") then
          ! Case (7) Stop processing options
          do while (iarg < max)
             iarg = iarg + 1
             call getarg_check(iarg,buf,ierr)
             if (ierr .ne. 0) return
             call store_arg(opts,buf)
          end do
       else if (buf(1:1) == '-' .and. in(buf(2:2), '-0123456789.')) then
          ! Case (8) Numeric
          if (.not. is_real(buf)) then
             write (error_unit,'(3a)') 'Error: expected a numeric argument: "', trim(buf), '"'
             ierr = 1
             return
          end if
          call store_arg(opts,buf)
       else if (buf(1:1) .ne. '-') then
          ! Case (9) Doesn't start with a dash
          call store_arg(opts,buf)
       else if (buf == '-') then
          ! Case (10) Just a dash
          call store_arg(opts,buf)
       else
          ! Anything else
          write (error_unit,'(3a)') 'Error: invalid argument: "', trim(buf), '"'
          ierr = 1
          return
       end if
    end do
    ierr = 0
  end subroutine process_command_line



  subroutine check_required_options(opts,ierr)
    ! Status: proved
    implicit none
    type(options_t),  target, intent(in) :: opts
    integer, intent(out) :: ierr

    type(opt_t), pointer :: opt
    integer :: iopt

    ierr = 0
    do iopt=1,opts%nopts
       opt => opts%opts(iopt)
       if (opt%required .and. .not. opt%found) then
          write (error_unit,'(3a)') 'Error: missing required parameter: "--', &
               trim(opt%name), '"'
          ierr = 2
          return
       end if
    end do
  end subroutine check_required_options


  subroutine parse_long_option(str,name,eqlc,val,ierr)
    ! Check and parse a long option of the form (i) "--<name>" or (ii)
    ! "--<name>=<val>".
    ! Input:
    !   str: String of the form above, possibly with trailing spaces.
    !        Here <name> must consist of characters for which is_name_char()
    !        is true, and must have at least one such character.
    ! Output:
    !   name:  The name of the option.
    !   eqlc:  For case (i), eqlc == ' '. For case (ii), eqlc == '='.
    !   val:   For case (i), val == ''. For case (ii), if val is a quoted string,
    !          the text between the quotes; otherwise, all characters between the
    !          '=' sign and the end of the string, excluding trailing spaces.
    !   ierr:  Upon success, 0. If the string is not formatted correctly, 1.
    ! On exit:
    !   ierr .eq. 0 ==> IsNameString(name) .and. eqlc ∈ " =" .and.
    !    (eqlc == '=' ==> HasValue(val))
    implicit none
    character(len=*), intent(in) :: str
    character(len=*), intent(out) :: name
    character(len=1), intent(out) :: eqlc
    character(len=*), intent(out) :: val
    integer, intent(out) :: ierr

    integer :: name_end, val_begin, val_end, lt

    lt = len_trim(str)
    ierr = 1
    val = ""
    eqlc = ' '

    ! Ensure there's at least one valid character for the name
    if (lt < 3) return
    if (str(1:2) .ne. "--") return
    if (.not. is_name_char(str(3:3))) return

    ! Parse name
    name_end = 2 + count_leading(str(3:),is_name_char)
    name = str(3:name_end)

    ! Parse '=' sign.
    if (name_end == lt) then
       ierr = 0
       return
    end if
    eqlc = str(name_end+1:name_end+1)
    if (eqlc .ne. '=') return

    ! Parse value
    val_begin = name_end+2
    val_end = lt
    if (val_begin > val_end) then
       ! Empty value
       ierr = 0
       return
    end if
    call unquote(str(val_begin:val_end),val,ierr)
  end subroutine parse_long_option


  subroutine unquote(str,val,ierr)
    ! Unquote a string, if appropriate.
    ! Input:
    !   str:  A string.
    !   val:  Unquoted version of str, as appropriate (see code).
    !   ierr: If str is processed successfully, 0. If not, 1.
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str
    character(len=*), intent(out) :: val
    integer, intent(out) :: ierr

    integer :: lt

    lt = len_trim(str)
    ierr = 1
    val = ''

    ! Case (i): length = 0
    if (lt == 0) then
       ierr = 0
       return
    end if

    ! Case (ii): length = 1. Must not be a quote
    if (lt == 1) then
       if (isquote(str)) then
          return
       else
          val = str(1:1)
          ierr = 0
          return
       end if
    end if

    ! Case (iii): length > 1. If str begins with a quote, we try to unquote,
    ! flagging an error if the last nonblank character does not match the initial
    ! quote. If str does not begin with a quote, return str itself. (We do not
    ! skip leading spaces to unquote.)
    if (isquote(str(1:1))) then
       if (str(lt:lt) .eq. str(1:1)) then
          ierr = 0
          val = str(2:lt-1)
       end if
    else
       val = str
       ierr = 0
    end if
  end subroutine unquote


  logical function isquote(c)
    implicit none
    character(len=1), intent(in) :: c

    isquote = c == '"' .or. c == "'"
  end function isquote


  function count_leading(str,p) result(count)
    ! Count the number of leading characters in str for which the predicate p is
    ! true.
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str
    interface
       logical function p(c)
         character(len=1), intent(in) :: c
       end function p
    end interface
    integer :: count, i

    count = 0
    do i=1,len(str)
       if (p(str(i:i))) then
          count = count + 1
       else
          exit
       end if
    end do
  end function count_leading


  logical function in(c,set)
    ! Determine whether the character c is in the set 'set'.
    ! Status: proved
    implicit none
    character(len=1), intent(in) :: c
    character(len=*), intent(in) :: set

    integer :: i

    in = .false.
    do i=1,len(set)
       in = c == set(i:i)
       if (in) return
    end do
  end function in


  function count_leading_set(str,set) result(count)
    ! Count the number of leading characters in str which are contained in the
    ! set 'set'.
    ! Status: proved
    implicit none
    character(len=*), intent(in) :: str,set
    integer :: count, i

    count = 0
    do i=1,len(str)
       if (in(str(i:i),set)) then
          count = count + 1
       else
          exit
       end if
    end do
  end function count_leading_set


  subroutine check_name(opt,name,abbrev)
    ! Status: proved
    ! Postcondition: opt%name .ne. name .and. (present(abbrev) ==> opt%abbrev .ne. abbrev)
    implicit none
    type(opt_t),      intent(in) :: opt
    character(len=*), intent(in) :: name
    character(len=1), optional, intent(in) :: abbrev

    if (opt%name == name) then
       write (error_unit,'(3a)') 'Error: duplicate definition of option "--', &
            trim(name), '"'
       stop
    end if
    if (present(abbrev)) then
       if (opt%abbrev == abbrev) then
          write (error_unit,'(3a)') 'Error: duplicate definition of option "-', &
               trim(abbrev), '"'
          stop
       end if
    end if
  end subroutine check_name


  function get_num_args(opts)
    ! Status: reviewed
    implicit none
    type(options_t), target, intent(in) :: opts
    integer :: get_num_args

    get_num_args = opts%nargs
  end function get_num_args


  subroutine get_arg(opts,index,str,ierr)
    ! Status: reviewed
    implicit none
    type(options_t), intent(in) :: opts
    integer, intent(in) :: index
    character(len=*), intent(out) :: str
    integer, intent(out) :: ierr

    if (index > opts%nargs .or. index < 1) then
       ierr = 1
       return
    end if
    str = opts%args(index)
  end subroutine get_arg

end module options
