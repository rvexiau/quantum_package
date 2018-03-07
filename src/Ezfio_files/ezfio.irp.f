BEGIN_PROVIDER [ character*(128), ezfio_filename ]
  implicit none
  BEGIN_DOC
  ! Name of EZFIO file. It is obtained from the QPACKAGE_INPUT environment
  ! variable if it is set, or as the 1st argument of the command line.
  END_DOC

  PROVIDE mpi_initialized
  
  ! Get the QPACKAGE_INPUT environment variable
  call getenv('QPACKAGE_INPUT',ezfio_filename)
  if (ezfio_filename == '') then
    ! Get from the command line
    integer                        :: iargc
    call getarg(0,ezfio_filename)
    if (iargc() /= 1) then
      print *, 'Missing EZFIO file name in the command line:'
      print *, trim(ezfio_filename)//' <ezfio_file>'
      stop 1
    endif
    call getarg(1,ezfio_filename)
  endif

  ! Check that file exists
  logical :: exists
  inquire(file=trim(ezfio_filename)//'/ezfio/creation',exist=exists)
  if (.not.exists) then
    print *, 'Error: file '//trim(ezfio_filename)//' does not exist'
    stop 1
  endif

  call ezfio_set_file(ezfio_filename)

END_PROVIDER

BEGIN_PROVIDER [ character*(128), ezfio_work_dir ]
 implicit none
 BEGIN_DOC
 ! EZFIO/work/
 END_DOC
 call ezfio_set_work_empty(.False.)
 ezfio_work_dir = trim(ezfio_filename)//'/work/'
END_PROVIDER

