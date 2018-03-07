subroutine ZMQ_selection(N_in, pt2)
  use f77_zmq
  use selection_types
  
  implicit none
  
  integer(ZMQ_PTR)               :: zmq_to_qp_run_socket , zmq_socket_pull
  integer, intent(in)            :: N_in
  type(selection_buffer)         :: b
  integer                        :: i, N
  integer, external              :: omp_get_thread_num
  double precision, intent(out)  :: pt2(N_states)
  integer, parameter             :: maxtasks=10000
  
  
  PROVIDE fragment_count

  N = max(N_in,1)
  if (.True.) then
    PROVIDE pt2_e0_denominator nproc
    PROVIDE psi_bilinear_matrix_columns_loc psi_det_alpha_unique psi_det_beta_unique
    PROVIDE psi_bilinear_matrix_rows psi_det_sorted_order psi_bilinear_matrix_order
    PROVIDE psi_bilinear_matrix_transp_rows_loc psi_bilinear_matrix_transp_columns
    PROVIDE psi_bilinear_matrix_transp_order

    call new_parallel_job(zmq_to_qp_run_socket,zmq_socket_pull,'selection')

    integer, external              :: zmq_put_psi
    integer, external              :: zmq_put_N_det_generators
    integer, external              :: zmq_put_N_det_selectors
    integer, external              :: zmq_put_dvector

    if (zmq_put_psi(zmq_to_qp_run_socket,1) == -1) then
      stop 'Unable to put psi on ZMQ server'
    endif
    if (zmq_put_N_det_generators(zmq_to_qp_run_socket, 1) == -1) then
      stop 'Unable to put N_det_generators on ZMQ server'
    endif
    if (zmq_put_N_det_selectors(zmq_to_qp_run_socket, 1) == -1) then
      stop 'Unable to put N_det_selectors on ZMQ server'
    endif
    if (zmq_put_dvector(zmq_to_qp_run_socket,1,'energy',pt2_e0_denominator,size(pt2_e0_denominator)) == -1) then
      stop 'Unable to put energy on ZMQ server'
    endif
    call create_selection_buffer(N, N*2, b)
  endif

  integer, external :: add_task_to_taskserver
  character*(20*maxtasks) :: task
  task = ' ' 

  integer :: k
  k=0
  do i= 1, N_det_generators
    k = k+1
    write(task(20*(k-1)+1:20*k),'(I9,1X,I9,''|'')') i, N
    if (k>=maxtasks) then
       k=0
       if (add_task_to_taskserver(zmq_to_qp_run_socket,task) == -1) then
         stop 'Unable to add task to task server'
       endif
    endif
  end do
  if (k > 0) then
    if (add_task_to_taskserver(zmq_to_qp_run_socket,task) == -1) then
      stop 'Unable to add task to task server'
    endif
  endif

  ASSERT (associated(b%det))
  ASSERT (associated(b%val))

  integer, external :: zmq_set_running
  if (zmq_set_running(zmq_to_qp_run_socket) == -1) then
    print *,  irp_here, ': Failed in zmq_set_running'
  endif

  !$OMP PARALLEL DEFAULT(shared)  SHARED(b, pt2)  PRIVATE(i) NUM_THREADS(nproc+1)
  i = omp_get_thread_num()
  if (i==0) then
    call selection_collector(zmq_socket_pull, b, N, pt2)
  else
    call selection_slave_inproc(i)
  endif
  !$OMP END PARALLEL
  call end_parallel_job(zmq_to_qp_run_socket, zmq_socket_pull, 'selection')
  do i=N_det+1,N_states
    pt2(i) = 0.d0
  enddo
  if (N_in > 0) then
    call fill_H_apply_buffer_no_selection(b%cur,b%det,N_int,0) 
    call copy_H_apply_buffer_to_wf()
    if (s2_eig.or.(N_states > 1) ) then
      call make_s2_eigenfunction
    endif
    call save_wavefunction
  endif
  call delete_selection_buffer(b)

end subroutine


subroutine selection_slave_inproc(i)
  implicit none
  integer, intent(in)            :: i

  call run_selection_slave(1,i,pt2_e0_denominator)
end

subroutine selection_collector(zmq_socket_pull, b, N, pt2)
  use f77_zmq
  use selection_types
  use bitmasks
  implicit none


  integer(ZMQ_PTR), intent(in)   :: zmq_socket_pull
  type(selection_buffer), intent(inout) :: b
  integer, intent(in) :: N
  double precision, intent(out)       :: pt2(N_states)
  double precision                   :: pt2_mwen(N_states)
  integer(ZMQ_PTR),external      :: new_zmq_to_qp_run_socket
  integer(ZMQ_PTR)               :: zmq_to_qp_run_socket

  integer(ZMQ_PTR), external     :: new_zmq_pull_socket

  integer :: msg_size, rc, more
  integer :: acc, i, j, robin, ntask
  double precision, pointer :: val(:)
  integer(bit_kind), pointer :: det(:,:,:)
  integer, allocatable :: task_id(:)
  type(selection_buffer) :: b2

  zmq_to_qp_run_socket = new_zmq_to_qp_run_socket()
  call create_selection_buffer(N, N*2, b2)
  allocate(task_id(N_det_generators))
  more = 1
  pt2(:) = 0d0
  pt2_mwen(:) = 0.d0
  do while (more == 1)
    call pull_selection_results(zmq_socket_pull, pt2_mwen, b2%val(1), b2%det(1,1,1), b2%cur, task_id, ntask)

    pt2(:) += pt2_mwen(:)
    do i=1, b2%cur
      call add_to_selection_buffer(b, b2%det(1,1,i), b2%val(i))
      if (b2%val(i) > b%mini) exit
    end do

    do i=1, ntask
      if(task_id(i) == 0) then
          print *,  "Error in collector"
      endif
      integer, external :: zmq_delete_task
      if (zmq_delete_task(zmq_to_qp_run_socket,zmq_socket_pull,task_id(i),more) == -1) then
        stop 'Unable to delete task'
      endif
    end do
  end do


  call delete_selection_buffer(b2)
  call sort_selection_buffer(b)
  call end_zmq_to_qp_run_socket(zmq_to_qp_run_socket)
end subroutine

