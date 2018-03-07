double precision function diag_S_mat_elem(key_i,Nint)
  implicit none
  use bitmasks
  include 'Utils/constants.include.F'

  integer                        :: Nint
  integer(bit_kind), intent(in)  :: key_i(Nint,2)
  BEGIN_DOC
! Returns <i|S^2|i>
  END_DOC
  integer                        :: nup, i
  integer(bit_kind)              :: xorvec(N_int_max)

  do i=1,Nint
    xorvec(i) = xor(key_i(i,1),key_i(i,2))
  enddo

  do i=1,Nint
    xorvec(i) = iand(xorvec(i),key_i(i,1))
  enddo

  nup = 0
  do i=1,Nint
    if (xorvec(i) /= 0_bit_kind) then
      nup += popcnt(xorvec(i))
    endif
  enddo
  diag_S_mat_elem = dble(nup)

end

subroutine get_s2(key_i,key_j,Nint,s2)
  implicit none
  use bitmasks
  BEGIN_DOC
  ! Returns <S^2>
  END_DOC
  integer, intent(in)            :: Nint
  integer(bit_kind), intent(in)  :: key_i(Nint,2)
  integer(bit_kind), intent(in)  :: key_j(Nint,2)
  double precision, intent(out)  :: s2
  integer                        :: exc(0:2,2,2)
  integer                        :: degree
  double precision               :: phase_spsm
  integer                        :: nup, i
  
  s2 = 0.d0
  !$FORCEINLINE
  call get_excitation_degree(key_i,key_j,degree,Nint)
  select case (degree)
    case(2)
      call get_double_excitation(key_j,key_i,exc,phase_spsm,Nint)
      if (exc(0,1,1) == 1) then   ! Mono alpha + mono-beta
        if ( (exc(1,1,1) == exc(1,2,2)).and.(exc(1,1,2) == exc(1,2,1)) ) then
          s2 =  -phase_spsm
        endif
      endif
    case(0)
      double precision, external :: diag_S_mat_elem
      !DIR$ FORCEINLINE
      s2 = diag_S_mat_elem(key_i,Nint)
  end select
end

BEGIN_PROVIDER [ double precision, S_z ]
&BEGIN_PROVIDER [ double precision, S_z2_Sz ]
 implicit none
 BEGIN_DOC
! z component of the Spin
 END_DOC

 S_z = 0.5d0*dble(elec_alpha_num-elec_beta_num)
 S_z2_Sz = S_z*(S_z-1.d0)

END_PROVIDER

BEGIN_PROVIDER [ double precision, expected_s2]
 implicit none
 BEGIN_DOC
! Expected value of S2 : S*(S+1)
 END_DOC
   logical :: has_expected_s2

   call ezfio_has_determinants_expected_s2(has_expected_s2)
   if (has_expected_s2) then
     call ezfio_get_determinants_expected_s2(expected_s2)
   else
     double precision :: S
     S = (elec_alpha_num-elec_beta_num)*0.5d0 
     expected_s2 = S * (S+1.d0)
   endif

END_PROVIDER 

BEGIN_PROVIDER [ double precision, s2_values, (N_states) ]
 implicit none
 BEGIN_DOC
! array of the averaged values of the S^2 operator on the various states
 END_DOC
 integer :: i
 call u_0_S2_u_0(s2_values,psi_coef,n_det,psi_det,N_int,N_states,psi_det_size)

END_PROVIDER



subroutine u_0_S2_u_0(e_0,u_0,n,keys_tmp,Nint,N_st,sze_8)
  use bitmasks
  implicit none
  BEGIN_DOC
  ! Computes e_0 = <u_0|S2|u_0>/<u_0|u_0>
  !
  ! n : number of determinants
  !
  END_DOC
  integer, intent(in)            :: n,Nint, N_st, sze_8
  double precision, intent(out)  :: e_0(N_st)
  double precision, intent(in)   :: u_0(sze_8,N_st)
  integer(bit_kind),intent(in)   :: keys_tmp(Nint,2,n)
  
  double precision, allocatable  :: v_0(:,:)
  double precision               :: u_dot_u,u_dot_v
  integer :: i,j
  allocate (v_0(sze_8,N_st))
  
  call S2_u_0_nstates(v_0,u_0,n,keys_tmp,Nint,N_st,sze_8)
  do i=1,N_st
    e_0(i) = u_dot_v(v_0(1,i),u_0(1,i),n)/u_dot_u(u_0(1,i),n) + S_z2_Sz
  enddo
end



subroutine S2_u_0(v_0,u_0,n,keys_tmp,Nint)
  use bitmasks
  implicit none
  BEGIN_DOC
  ! Computes v_0 = S^2|u_0>
  !
  ! n : number of determinants
  !
  END_DOC
  integer, intent(in)            :: n,Nint
  double precision, intent(out)  :: v_0(n)
  double precision, intent(in)   :: u_0(n)
  integer(bit_kind),intent(in)   :: keys_tmp(Nint,2,n)
  call S2_u_0_nstates(v_0,u_0,n,keys_tmp,Nint,1,n)
end

subroutine S2_u_0_nstates(v_0,u_0,n,keys_tmp,Nint,N_st,sze_8)
  use bitmasks
  implicit none
  BEGIN_DOC
  ! Computes v_0  = S^2|u_0>
  !
  ! n : number of determinants
  !
  END_DOC
  integer, intent(in)            :: N_st,n,Nint, sze_8
  double precision, intent(out)  :: v_0(sze_8,N_st)
  double precision, intent(in)   :: u_0(sze_8,N_st)
  integer(bit_kind),intent(in)   :: keys_tmp(Nint,2,n)
  double precision               :: s2_tmp
  double precision, allocatable  :: vt(:,:)
  integer                        :: i,j,k,l, jj,ii
  integer                        :: i0, j0
  
  integer, allocatable           :: shortcut(:,:), sort_idx(:,:)
  integer(bit_kind), allocatable :: sorted(:,:,:), version(:,:,:)
  integer(bit_kind)              :: sorted_i(Nint)
  
  integer                        :: sh, sh2, ni, exa, ext, org_i, org_j, endi, istate
  

  ASSERT (Nint > 0)
  ASSERT (Nint == N_int)
  ASSERT (n>0)
  PROVIDE ref_bitmask_energy 

  allocate (shortcut(0:n+1,2), sort_idx(n,2), sorted(Nint,n,2), version(Nint,n,2))
  v_0 = 0.d0

  call sort_dets_ab_v(keys_tmp, sorted(1,1,1), sort_idx(1,1), shortcut(0,1), version(1,1,1), n, Nint)
  call sort_dets_ba_v(keys_tmp, sorted(1,1,2), sort_idx(1,2), shortcut(0,2), version(1,1,2), n, Nint)
  
  !$OMP PARALLEL DEFAULT(NONE)                                       &
      !$OMP PRIVATE(i,s2_tmp,j,k,jj,vt,ii,sh,sh2,ni,exa,ext,org_i,org_j,endi,sorted_i,istate)&
      !$OMP SHARED(n,u_0,keys_tmp,Nint,v_0,sorted,shortcut,sort_idx,version,N_st,sze_8)
  allocate(vt(sze_8,N_st))
  vt = 0.d0
  
  !$OMP DO SCHEDULE(dynamic)
  do sh=1,shortcut(0,1)
    do sh2=sh,shortcut(0,1)
      exa = 0
      do ni=1,Nint
        exa = exa + popcnt(xor(version(ni,sh,1), version(ni,sh2,1)))
      end do
      if(exa > 2) then
        cycle
      end if
      
      do i=shortcut(sh,1),shortcut(sh+1,1)-1
        org_i = sort_idx(i,1)
        if(sh==sh2) then
          endi = i-1
        else
          endi = shortcut(sh2+1,1)-1
        end if
        do ni=1,Nint
          sorted_i(ni) = sorted(ni,i,1)
        enddo
        
        do j=shortcut(sh2,1),endi
          org_j = sort_idx(j,1)
          ext = exa
          do ni=1,Nint
            ext = ext + popcnt(xor(sorted_i(ni), sorted(ni,j,1)))
          end do
          if(ext <= 4) then
            call get_s2(keys_tmp(1,1,org_i),keys_tmp(1,1,org_j),Nint,s2_tmp)
            do istate=1,N_st
              vt (org_i,istate) = vt (org_i,istate) + s2_tmp*u_0(org_j,istate)
              vt (org_j,istate) = vt (org_j,istate) + s2_tmp*u_0(org_i,istate)
            enddo
          endif
        enddo
      enddo
    enddo
  enddo
  !$OMP END DO NOWAIT
  
  !$OMP DO SCHEDULE(dynamic)
  do sh=1,shortcut(0,2)
    do i=shortcut(sh,2),shortcut(sh+1,2)-1
      org_i = sort_idx(i,2)
      do j=shortcut(sh,2),i-1
        org_j = sort_idx(j,2)
        ext = 0
        do ni=1,Nint
          ext = ext + popcnt(xor(sorted(ni,i,2), sorted(ni,j,2)))
        end do
        if(ext == 4) then
          call get_s2(keys_tmp(1,1,org_i),keys_tmp(1,1,org_j),Nint,s2_tmp)
          do istate=1,N_st
            vt (org_i,istate) = vt (org_i,istate) + s2_tmp*u_0(org_j,istate)
            vt (org_j,istate) = vt (org_j,istate) + s2_tmp*u_0(org_i,istate)
          enddo
        end if
      end do
    end do
  enddo
  !$OMP END DO NOWAIT
  
  do istate=1,N_st
    do i=n,1,-1
      !$OMP ATOMIC
      v_0(i,istate) = v_0(i,istate) + vt(i,istate)
    enddo
  enddo

  deallocate(vt)
  !$OMP END PARALLEL
  
  do i=1,n
    call get_s2(keys_tmp(1,1,i),keys_tmp(1,1,i),Nint,s2_tmp)
    do istate=1,N_st
      v_0(i,istate) += s2_tmp * u_0(i,istate)
    enddo
  enddo

  deallocate (shortcut, sort_idx, sorted, version)
end







subroutine get_uJ_s2_uI(psi_keys_tmp,psi_coefs_tmp,n,nmax_coefs,nmax_keys,s2,nstates)
  implicit none
  use bitmasks
  integer, intent(in)            :: n,nmax_coefs,nmax_keys,nstates
  integer(bit_kind), intent(in)  :: psi_keys_tmp(N_int,2,nmax_keys)
  double precision, intent(in)   :: psi_coefs_tmp(nmax_coefs,nstates)
  double precision, intent(out)  :: s2(nstates,nstates)
  double precision               :: s2_tmp,accu
  integer                        :: i,j,l,jj,ll,kk
  integer, allocatable           :: idx(:)
  BEGIN_DOC
  ! returns the matrix elements of S^2 "s2(i,j)" between the "nstates" states
  ! psi_coefs_tmp(:,i) and psi_coefs_tmp(:,j)
  END_DOC
  s2 = 0.d0
  do ll = 1, nstates
    do jj = 1, nstates
      accu = 0.d0
      !$OMP PARALLEL DEFAULT(NONE)                                   &
          !$OMP PRIVATE (i,j,kk,idx,s2_tmp)                          &
          !$OMP SHARED (ll,jj,psi_keys_tmp,psi_coefs_tmp,N_int,n,nstates)&
          !$OMP REDUCTION(+:accu)
      allocate(idx(0:n))
      !$OMP DO SCHEDULE(dynamic)
      do i = n,1,-1   ! Better OMP scheduling
        call get_s2(psi_keys_tmp(1,1,i),psi_keys_tmp(1,1,i),N_int,s2_tmp)
        accu += psi_coefs_tmp(i,ll) * s2_tmp * psi_coefs_tmp(i,jj)
        call filter_connected(psi_keys_tmp,psi_keys_tmp(1,1,i),N_int,i-1,idx)
        do kk=1,idx(0)
          j = idx(kk)
          call get_s2(psi_keys_tmp(1,1,i),psi_keys_tmp(1,1,j),N_int,s2_tmp)
          accu += psi_coefs_tmp(i,ll) * s2_tmp * psi_coefs_tmp(j,jj) + psi_coefs_tmp(i,jj) * s2_tmp * psi_coefs_tmp(j,ll)
        enddo
      enddo
      !$OMP END DO
      deallocate(idx)
      !$OMP END PARALLEL
      s2(ll,jj) += accu
    enddo
  enddo
  do i = 1, nstates
    do j =i+1,nstates
      accu = 0.5d0 * (s2(i,j) + s2(j,i))
      s2(i,j) = accu
      s2(j,i) = accu
    enddo
  enddo
end

subroutine diagonalize_s2_betweenstates(keys_tmp,u_0,n,nmax_keys,nmax_coefs,nstates,s2_eigvalues)
  BEGIN_DOC
  ! You enter with nstates vectors in u_0 that may be coupled by S^2
  ! The subroutine diagonalize the S^2 operator in the basis of these states.
  ! The vectors that you obtain in output are no more coupled by S^2,
  ! which does not necessary mean that they are eigenfunction of S^2.
  ! n,nmax,nstates = number of determinants, physical dimension of the arrays and number of states
  ! keys_tmp = array of integer(bit_kind) that represents the determinants
  ! psi_coefs(i,j) = coeff of the ith determinant in the jth state
  ! VECTORS ARE SUPPOSED TO BE ORTHONORMAL IN INPUT
  END_DOC
  implicit none
  use bitmasks
  integer, intent(in)            :: n,nmax_keys,nmax_coefs,nstates
  integer(bit_kind), intent(in)  :: keys_tmp(N_int,2,nmax_keys)
  double precision, intent(inout) :: u_0(nmax_coefs,nstates)
  double precision, intent(out)  :: s2_eigvalues(nstates)
  
  
  double precision,allocatable   :: s2(:,:),overlap(:,:)
  double precision, allocatable  :: eigvectors(:,:,:)
  integer                        :: i,j,k
  double precision, allocatable  :: psi_coefs_tmp(:,:)
  double precision               :: accu,coef_contract
  double precision               :: u_dot_u,u_dot_v
  
  print*,''
  print*,'*********************************************************************'
  print*,'Cleaning the various vectors by diagonalization of the S^2 matrix ...'
  print*,''
  print*,'nstates = ',nstates
  allocate(s2(nstates,nstates),overlap(nstates,nstates))
  overlap = 0.d0
  call dgemm('T','N',nstates,nstates,n, 1.d0, u_0, size(u_0,1),      &
      u_0, size(u_0,1), 0.d0, overlap, size(overlap,1))
  call ortho_lowdin(overlap,size(overlap,1),nstates,u_0,size(u_0,1),n)
  
  double precision, allocatable  :: v_0(:,:)
  allocate ( v_0(size(u_0,1),nstates) )
  call S2_u_0_nstates(v_0,u_0,n,keys_tmp,N_int,nstates,size(u_0,1))
  
  call dgemm('T','N',nstates,nstates,n, 1.d0, u_0, size(u_0,1),      &
      v_0, size(v_0,1), 0.d0, s2, size(s2,1))
  
  print*,'S^2 matrix in the basis of the states considered'
  do i = 1, nstates
    write(*,'(100(F5.2,1X))')s2(i,:)
  enddo
  
  double precision               :: accu_precision_diag,accu_precision_of_diag
  accu_precision_diag = 0.d0
  accu_precision_of_diag = 0.d0
  do i = 1, nstates
    ! Do not combine states of the same spin symmetry
    do j = i+1, nstates
      if( dabs(s2(i,i) - s2(j,j)) .le.0.5d0) then
        s2(i,j) = 0.d0
        s2(j,i) = 0.d0
      endif
    enddo
    ! Do not rotate if the diagonal is correct
    if( dabs(s2(i,i) - expected_s2).le.5.d-3) then
      do j = 1, nstates
        if (j==i) cycle
        s2(i,j) = 0.d0
        s2(j,i) = 0.d0
      enddo
    endif
  enddo
  
  print*,'Modified S^2 matrix that will be diagonalized'
  do i = 1, nstates
    write(*,'(10(F5.2,1X))')s2(i,:)
    s2(i,i) = s2(i,i)
  enddo
  
  allocate(eigvectors(nstates,nstates,2))
!  call svd(s2, size(s2,1), eigvectors, size(eigvectors,1), s2_eigvalues,&
!      eigvectors(1,1,2), size(eigvectors,1), nstates, nstates)

  call lapack_diagd(s2_eigvalues,eigvectors,s2,nstates,nstates)
  print*,'Eigenvalues'
  double precision :: t(nstates)
  integer :: iorder(nstates)
  do i = 1, nstates
    t(i) = dabs(s2_eigvalues(i))
    iorder(i) = i
  enddo
  call dsort(t,iorder,nstates)

  do i = 1, nstates
    s2_eigvalues(i) = t(i)
    do j=1,nstates
      eigvectors(j,i,2) = eigvectors(j,iorder(i),1)
    enddo
    print*,'s2 = ',s2_eigvalues(i)
  enddo
  
  allocate(psi_coefs_tmp(nmax_coefs,nstates))
  psi_coefs_tmp = 0.d0
  do j = 1, nstates
    do k = 1, nstates
      coef_contract =  eigvectors(k,j,2)    !  <phi_k|Psi_j>
      do i = 1, n_det
        psi_coefs_tmp(i,j) += u_0(i,k) * coef_contract
      enddo
    enddo
  enddo
  do j = 1, nstates
    accu = 1.d0/u_dot_u(psi_coefs_tmp(1,j),n_det)
    do i = 1, n_det
      u_0(i,j) = psi_coefs_tmp(i,j) * accu
    enddo
  enddo
  
  deallocate(s2,v_0,eigvectors,psi_coefs_tmp,overlap )
  
end

subroutine i_S2_psi_minilist(key,keys,idx_key,N_minilist,coef,Nint,Ndet,Ndet_max,Nstate,i_S2_psi_array)
  use bitmasks
  implicit none
  integer, intent(in)            :: Nint, Ndet,Ndet_max,Nstate,idx_key(Ndet), N_minilist
  integer(bit_kind), intent(in)  :: keys(Nint,2,Ndet)
  integer(bit_kind), intent(in)  :: key(Nint,2)
  double precision, intent(in)   :: coef(Ndet_max,Nstate)
  double precision, intent(out)  :: i_S2_psi_array(Nstate)
  
  integer                        :: i, ii,j, i_in_key, i_in_coef
  double precision               :: phase
  integer                        :: exc(0:2,2,2)
  double precision               :: s2ij
  integer                        :: idx(0:Ndet)
  BEGIN_DOC
! Computes <i|S2|Psi> = \sum_J c_J <i|S2|J>.
!
! Uses filter_connected_i_H_psi0 to get all the |J> to which |i>
! is connected. The |J> are searched in short pre-computed lists.
  END_DOC
  
  ASSERT (Nint > 0)
  ASSERT (N_int == Nint)
  ASSERT (Nstate > 0)
  ASSERT (Ndet > 0)
  ASSERT (Ndet_max >= Ndet)
  i_S2_psi_array = 0.d0
  
  call filter_connected_i_H_psi0(keys,key,Nint,N_minilist,idx)
  if (Nstate == 1) then

    do ii=1,idx(0)
      i_in_key = idx(ii)
      i_in_coef = idx_key(idx(ii))
      !DIR$ FORCEINLINE
      call get_s2(keys(1,1,i_in_key),key,Nint,s2ij)
      ! TODO : Cache misses
      i_S2_psi_array(1) = i_S2_psi_array(1) + coef(i_in_coef,1)*s2ij
    enddo

  else

    do ii=1,idx(0)
      i_in_key = idx(ii)
      i_in_coef = idx_key(idx(ii))
      !DIR$ FORCEINLINE
      call get_s2(keys(1,1,i_in_key),key,Nint,s2ij)
      do j = 1, Nstate
        i_S2_psi_array(j) = i_S2_psi_array(j) + coef(i_in_coef,j)*s2ij
      enddo
    enddo

  endif

end
