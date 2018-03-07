subroutine four_index_transform(map_a,map_c,matrix_B,LDB,            &
      i_start, j_start, k_start, l_start,                            &
      i_end  , j_end  , k_end  , l_end  ,                            &
      a_start, b_start, c_start, d_start,                            &
      a_end  , b_end  , c_end  , d_end  )
  implicit none
  use map_module
  use mmap_module
  BEGIN_DOC
! Performs a four-index transformation of map_a(N^4) into map_c(M^4) using b(NxM)
! C_{abcd} = \sum_{ijkl} A_{ijkl}.B_{ia}.B_{jb}.B_{kc}.B_{ld}
! Loops run over *_start->*_end
  END_DOC
  type(map_type), intent(in)     :: map_a
  type(map_type), intent(inout)  :: map_c
  integer, intent(in)            :: LDB
  double precision, intent(in)   :: matrix_B(LDB,*)
  integer, intent(in)            :: i_start, j_start, k_start, l_start
  integer, intent(in)            :: i_end  , j_end  , k_end  , l_end
  integer, intent(in)            :: a_start, b_start, c_start, d_start
  integer, intent(in)            :: a_end  , b_end  , c_end  , d_end

  double precision, allocatable  :: T(:,:), U(:,:,:), V(:,:)
  double precision, allocatable  :: T2d(:,:), V2d(:,:)
  integer                        :: i_max, j_max, k_max, l_max
  integer                        :: i_min, j_min, k_min, l_min
  integer                        :: i, j, k, l, ik, ll
  integer                        :: l_start_block, l_end_block, l_block
  integer                        :: a, b, c, d
  double precision, external     :: get_ao_bielec_integral
  integer*8                      :: ii
  integer(key_kind)              :: idx
  real(integral_kind)            :: tmp
  integer(key_kind), allocatable :: key(:)
  real(integral_kind), allocatable :: value(:)
  integer*8, allocatable         :: l_pointer(:)

  ASSERT (k_start == i_start)
  ASSERT (l_start == j_start)
  ASSERT (a_start == c_start)
  ASSERT (b_start == d_start)

  i_min = min(i_start,a_start)
  i_max = max(i_end  ,a_end  )
  j_min = min(j_start,b_start)
  j_max = max(j_end  ,b_end  )
  k_min = min(k_start,c_start)
  k_max = max(k_end  ,c_end  )
  l_min = min(l_start,d_start)
  l_max = max(l_end  ,d_end  )

  ASSERT (0 < i_max)
  ASSERT (0 < j_max)
  ASSERT (0 < k_max)
  ASSERT (0 < l_max)
  ASSERT (LDB >= i_max)
  ASSERT (LDB >= j_max)
  ASSERT (LDB >= k_max)
  ASSERT (LDB >= l_max)

  integer*4, allocatable         :: a_array_ik(:)
  integer*4, allocatable         :: a_array_j(:)
  double precision, allocatable  :: a_array_value(:)

  integer*8 :: new_size
  new_size = max(1024_8, 10_8 * map_a % n_elements )

  allocate(a_array_ik(new_size), a_array_j(new_size), a_array_value(new_size))

  integer :: ipass, npass
  integer*8 :: tempspace

  tempspace = (new_size * 16_8) / (1024_8 * 1024_8)
  npass = int(min(int(l_end-l_start,8),1_8 + tempspace / 2048_8),4)   ! 2 GiB of scratch space
  l_block = (l_end-l_start+1)/npass

  ipass = 0
  do l_start_block = l_start, l_end, l_block
    ipass = ipass+1
    print *,  'Pass ', ipass
    l_end_block = min(l_end, l_start_block+l_block-1)

    allocate(l_pointer(l_start_block:l_end_block+1), value((i_max*k_max)) )
    ii = 1_8
    !$OMP PARALLEL DEFAULT(SHARED) PRIVATE(i,j,k,l,ik,idx) 
    do l=l_start_block,l_end_block
      !$OMP SINGLE
      l_pointer(l) = ii
      !$OMP END SINGLE
      do j=j_start,j_end
        !$OMP DO SCHEDULE(static,16)
        do k=k_start,k_end
          do i=i_start,i_end
            ik = (i-i_start+1) + (k-k_start)*(k_end-k_start+1)
            call bielec_integrals_index(i,j,k,l,idx)
            call map_get(map_a,idx,value(ik))
          enddo
        enddo
        !$OMP END DO

        !$OMP SINGLE
        ik=0
        do k=k_start,k_end
          do i=i_start,i_end
            ik = ik+1
            tmp=value(ik)
            if (tmp /= 0.d0) then
              a_array_ik(ii) = ik
              a_array_j(ii)  = j
              a_array_value(ii) = tmp
              ii=ii+1_8
            endif
          enddo
        enddo
        !$OMP END SINGLE
      enddo
    enddo
    !$OMP SINGLE
    a_array_ik(ii) = 0
    a_array_j(ii)  = 0
    a_array_value(ii) = 0.d0
    l_pointer(l_end_block+1) = ii
    !$OMP END SINGLE
    !$OMP END PARALLEL  
    deallocate(value)

  !INPUT DATA
  !open(unit=10,file='INPUT',form='UNFORMATTED')
  !write(10) i_start, j_start, i_end, j_end
  !write(10) a_start, b_start, a_end, b_end
  !write(10) LDB, mo_tot_num
  !write(10) matrix_B(1:LDB,1:mo_tot_num)
  !idx=size(a_array)
  !write(10) idx
  !write(10) a_array
  !write(10) l_pointer
  !close(10)
  !open(unit=10,file='OUTPUT',form='FORMATTED')
  ! END INPUT DATA


    !$OMP PARALLEL DEFAULT(NONE) SHARED(a_array_ik,a_array_j,a_array_value,&
        !$OMP  a_start,a_end,b_start,b_end,c_start,c_end,d_start,d_end,&
        !$OMP  i_start,i_end,j_start,j_end,k_start,k_end,l_start_block,l_end_block,&
        !$OMP  i_min,i_max,j_min,j_max,k_min,k_max,l_min,l_max,      &
        !$OMP  map_c,matrix_B,l_pointer)                             &
        !$OMP  PRIVATE(key,value,T,U,V,i,j,k,l,idx,ik,ll,            &
        !$OMP  a,b,c,d,tmp,T2d,V2d,ii,p,q)
    allocate( key(i_max*j_max*k_max), value(i_max*j_max*k_max) )
    allocate( U(a_start:a_end, c_start:c_end, b_start:b_end) )



    allocate( T2d((i_end-i_start+1)*(k_end-k_start+1), j_start:j_end), &
              V2d((i_end-i_start+1)*(k_end-k_start+1), b_start:b_end), &
              V(i_start:i_end, k_start:k_end), &
              T(k_start:k_end, a_start:a_end))


    !$OMP DO SCHEDULE(dynamic)
    do d=d_start,d_end
      U = 0.d0
      do l=l_start_block,l_end_block
        if (dabs(matrix_B(l,d)) < 1.d-10) then
          cycle
        endif
        
        ii=l_pointer(l)
        do j=j_start,j_end
          !DIR$ VECTOR NONTEMPORAL
          T2d(:,j) = 0.d0
          !DIR$ IVDEP
          do while (j == a_array_j(ii))
            T2d(a_array_ik(ii),j) = a_array_value(ii)
            ii = ii + 1_8
          enddo
        enddo

        call DGEMM('N','N', (i_end-i_start+1)*(k_end-k_start+1)     ,&
            (b_end-b_start+1), (j_end-j_start+1), 1.d0,              &
            T2d(1,j_start), size(T2d,1),                             &
            matrix_B(j_start,b_start), size(matrix_B,1),0.d0,        &
            V2d(1,b_start), size(V2d,1) )

        do b=b_start,b_end
          ik = 0
          do k=k_start,k_end
            do i=i_start,i_end
              ik = ik+1
              V(i,k) = V2d(ik,b)
            enddo
          enddo

  !        T = 0.d0
  !        do a=a_start,a_end
  !          do k=k_start,k_end
  !            do i=i_start,i_end
  !              T(k,a) = T(k,a) + V(k,i)*matrix_B(i,a)
  !            enddo
  !          enddo
  !        enddo
          call DGEMM('N','N', (k_end-k_start+1), (a_end-a_start+1),    &
              (i_end-i_start+1), 1.d0,                                 &
              V(i_start,k_start), size(V,1),                           &
              matrix_B(i_start,a_start), size(matrix_B,1),0.d0,        &
              T(k_start,a_start), size(T,1) )

  !        do c=c_start,c_end
  !          do a=a_start,a_end
  !            do k=k_start,k_end
  !              U(a,c,b) = U(a,c,b) + T(k,a)*matrix_B(k,c)*matrix_B(l,d)
  !            enddo
  !          enddo
  !        enddo
          call DGEMM('T','N', (a_end-a_start+1), (c_end-c_start+1),    &
              (k_end-k_start+1), matrix_B(l, d),                       &
              T(k_start,a_start), size(T,1),                           &
              matrix_B(k_start,c_start), size(matrix_B,1), 1.d0,       &
              U(a_start,c_start,b), size(U,1) )
        enddo
      enddo

      idx = 0_8

! TODO : Remove symmetry in storage
      integer :: p, q
      do b=b_start,d
        q = b+ishft(d*d-d,-1)
        do c=c_start,c_end
          p = a_start+ishft(c*c-c,-1)
          do a=a_start,min(b,c)
            if (dabs(U(a,c,b)) < 1.d-15) then
              cycle
            endif
            if ((a==b).and.(p>q)) cycle
            p = p+1
            idx = idx+1_8
            call bielec_integrals_index(a,b,c,d,key(idx))
!print *,  int(key(idx),4), int(a,2),int(b,2),int(c,2),int(d,2), p, q
            value(idx) = U(a,c,b)
          enddo
        enddo
      enddo






      !$OMP CRITICAL
      call map_update(map_c, key, value, idx,1.d-15) 
      !$OMP END CRITICAL

  !WRITE OUTPUT
  ! OMP CRITICAL
  !print *,  d
  !do b=b_start,d
  !  do c=c_start,c_end
  !    do a=a_start,min(b,c)
  !      if (dabs(U(a,c,b)) < 1.d-15) then
  !        cycle
  !      endif
  !      write(10,*) d,c,b,a,U(a,c,b)
  !    enddo
  !  enddo
  !enddo
  ! OMP END CRITICAL
  !END WRITE OUTPUT


    enddo
    !$OMP END DO

    deallocate(key,value,V,T)
    !$OMP END PARALLEL
    call map_merge(map_c)

    deallocate(l_pointer)
  enddo
  deallocate(a_array_ik,a_array_j,a_array_value)

end
