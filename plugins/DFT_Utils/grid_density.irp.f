 BEGIN_PROVIDER [integer, n_points_integration_angular]
 implicit none
 n_points_integration_angular = 110
 END_PROVIDER 

BEGIN_PROVIDER [integer, n_points_radial_grid]
 implicit none
 n_points_radial_grid = 100
END_PROVIDER 


 BEGIN_PROVIDER [double precision, angular_quadrature_points, (n_points_integration_angular,3) ]
&BEGIN_PROVIDER [double precision, weights_angular_points, (n_points_integration_angular)]
 implicit none
 BEGIN_DOC
! weights and grid points for the integration on the angular variables on 
! the unit sphere centered on (0,0,0)
! According to the LEBEDEV scheme
 END_DOC
 angular_quadrature_points = 0.d0
 weights_angular_points = 0.d0
!call cal_quad(n_points_integration_angular, angular_quadrature_points,weights_angular_points)
 include 'constants.include.F'
 integer :: i,n
 double precision :: accu
 double precision :: degre_rad
 degre_rad = pi/180.d0
 accu = 0.d0
 double precision :: x(n_points_integration_angular),y(n_points_integration_angular),z(n_points_integration_angular),w(n_points_integration_angular)
 call LD0110(X,Y,Z,W,N)
 do i = 1, n_points_integration_angular
  angular_quadrature_points(i,1) = x(i)
  angular_quadrature_points(i,2) = y(i)
  angular_quadrature_points(i,3) = z(i)
  weights_angular_points(i) = w(i) * 4.d0 * pi
  accu += w(i)
 enddo
!do i = 1, n_points_integration_angular
! accu += weights_angular_integration_lebedev(i)
! weights_angular_points(i) = weights_angular_integration_lebedev(i) * 4.d0 * pi
! angular_quadrature_points(i,1) = dcos ( degre_rad *  theta_angular_integration_lebedev(i)) & 
!                                * dsin ( degre_rad *  phi_angular_integration_lebedev(i))
! angular_quadrature_points(i,2) = dsin ( degre_rad *  theta_angular_integration_lebedev(i)) & 
!                                * dsin ( degre_rad *  phi_angular_integration_lebedev(i))
! angular_quadrature_points(i,3) = dcos ( degre_rad *  phi_angular_integration_lebedev(i))   

!!weights_angular_points(i) = weights_angular_integration_lebedev(i)
!!angular_quadrature_points(i,1) = dcos ( degre_rad *  phi_angular_integration_lebedev(i)) & 
!!                               * dsin ( degre_rad *  theta_angular_integration_lebedev(i))
!!angular_quadrature_points(i,2) = dsin ( degre_rad *  phi_angular_integration_lebedev(i)) & 
!!                               * dsin ( degre_rad *  theta_angular_integration_lebedev(i))
!!angular_quadrature_points(i,3) = dcos ( degre_rad *  theta_angular_integration_lebedev(i))   
!enddo
 print*,'ANGULAR'
 print*,''
 print*,'accu = ',accu
 ASSERT( dabs(accu - 1.D0) < 1.d-10)

END_PROVIDER 

BEGIN_PROVIDER [integer , m_knowles]
 implicit none
 BEGIN_DOC
! value of the "m" parameter in the equation (7) of the paper of Knowles (JCP, 104, 1996)
 END_DOC
 m_knowles = 3
END_PROVIDER 

 BEGIN_PROVIDER [double precision, grid_points_radial, (n_points_radial_grid)]
&BEGIN_PROVIDER [double precision, dr_radial_integral]

 implicit none
 BEGIN_DOC
! points in [0,1] to map the radial integral [0,\infty] 
 END_DOC
 dr_radial_integral = 1.d0/dble(n_points_radial_grid-1)
 integer :: i
 do i = 1, n_points_radial_grid-1
  grid_points_radial(i) = (i-1) * dr_radial_integral
 enddo

END_PROVIDER 

BEGIN_PROVIDER [double precision, grid_points_per_atom, (3,n_points_integration_angular,n_points_radial_grid,nucl_num)]
 BEGIN_DOC
! points for integration over space
 END_DOC
 implicit none
 integer :: i,j,k
 double precision :: dr,x_ref,y_ref,z_ref
 double precision :: knowles_function
 do i = 1, nucl_num
  x_ref = nucl_coord(i,1)
  y_ref = nucl_coord(i,2)
  z_ref = nucl_coord(i,3)
  do j = 1, n_points_radial_grid-1
   double precision :: x,r
   x = grid_points_radial(j) ! x value for the mapping of the [0, +\infty] to [0,1]
   r = knowles_function(alpha_knowles(int(nucl_charge(i))),m_knowles,x) ! value of the radial coordinate for the integration 
   do k = 1, n_points_integration_angular  ! explicit values of the grid points centered around each atom 
    grid_points_per_atom(1,k,j,i) = x_ref + angular_quadrature_points(k,1) * r
    grid_points_per_atom(2,k,j,i) = y_ref + angular_quadrature_points(k,2) * r
    grid_points_per_atom(3,k,j,i) = z_ref + angular_quadrature_points(k,3) * r
   enddo
  enddo
 enddo
END_PROVIDER 

BEGIN_PROVIDER [double precision, weight_functions_at_grid_points, (n_points_integration_angular,n_points_radial_grid,nucl_num) ]
 BEGIN_DOC 
! Weight function at grid points : w_n(r) according to the equation (22) of Becke original paper (JCP, 88, 1988)
! the "n" discrete variable represents the nucleis which in this array is represented by the last dimension 
! and the points are labelled by the other dimensions
 END_DOC
 implicit none
 integer :: i,j,k,l,m
 double precision :: r(3)
 double precision :: accu,cell_function_becke
 double precision :: tmp_array(nucl_num)
 ! run over all points in space
  do j = 1, nucl_num  ! that are referred to each atom 
   do k = 1, n_points_radial_grid -1  !for each radial grid attached to the "jth" atom
    do l = 1, n_points_integration_angular ! for each angular point attached to the "jth" atom
     r(1) = grid_points_per_atom(1,l,k,j)
     r(2) = grid_points_per_atom(2,l,k,j)
     r(3) = grid_points_per_atom(3,l,k,j)
     accu = 0.d0
     do i = 1, nucl_num ! For each of these points in space, ou need to evaluate the P_n(r)
                        ! function defined for each atom "i" by equation (13) and (21) with k == 3
      tmp_array(i) = cell_function_becke(r,i) ! P_n(r)
      ! Then you compute the summ the P_n(r) function for each of the "r" points
      accu += tmp_array(i)
     enddo
     accu = 1.d0/accu
     weight_functions_at_grid_points(l,k,j) = tmp_array(j) * accu 
    enddo
   enddo
  enddo


END_PROVIDER 

BEGIN_PROVIDER [double precision, final_weight_functions_at_grid_points, (n_points_integration_angular,n_points_radial_grid,nucl_num) ]
 BEGIN_DOC 
! Weight function at grid points : w_n(r) according to the equation (22) of Becke original paper (JCP, 88, 1988)
! the "n" discrete variable represents the nucleis which in this array is represented by the last dimension 
! and the points are labelled by the other dimensions
 END_DOC
 implicit none
 integer :: i,j,k,l,m
 double precision :: r(3)
 double precision :: accu,cell_function_becke
 double precision :: tmp_array(nucl_num)
 double precision :: contrib_integration,x
 double precision :: derivative_knowles_function,knowles_function
 ! run over all points in space
  do j = 1, nucl_num  ! that are referred to each atom 
   do i = 1, n_points_radial_grid -1  !for each radial grid attached to the "jth" atom
    x = grid_points_radial(i) ! x value for the mapping of the [0, +\infty] to [0,1]
    do k = 1, n_points_integration_angular ! for each angular point attached to the "jth" atom
     contrib_integration = derivative_knowles_function(alpha_knowles(int(nucl_charge(j))),m_knowles,x) & 
                          *knowles_function(alpha_knowles(int(nucl_charge(j))),m_knowles,x)**2          
     final_weight_functions_at_grid_points(k,i,j) = weights_angular_points(k)  * weight_functions_at_grid_points(k,i,j) * contrib_integration * dr_radial_integral
    enddo
   enddo
  enddo

END_PROVIDER 


 BEGIN_PROVIDER [double precision, one_body_dm_mo_alpha_at_grid_points, (n_points_integration_angular,n_points_radial_grid,nucl_num,N_states) ]
&BEGIN_PROVIDER [double precision, one_body_dm_mo_beta_at_grid_points, (n_points_integration_angular,n_points_radial_grid,nucl_num,N_states) ]
 implicit none
 integer :: i,j,k,l,m,i_state
 double precision :: contrib
 double precision :: r(3)
 double precision :: aos_array(ao_num),mos_array(mo_tot_num)
 do i_state = 1, N_states
  do j = 1, nucl_num
   do k = 1, n_points_radial_grid 
    do l = 1, n_points_integration_angular
     one_body_dm_mo_alpha_at_grid_points(l,k,j,i_state) = 0.d0
     one_body_dm_mo_beta_at_grid_points(l,k,j,i_state) = 0.d0
     r(1) = grid_points_per_atom(1,l,k,j)
     r(2) = grid_points_per_atom(2,l,k,j)
     r(3) = grid_points_per_atom(3,l,k,j)

     call give_all_mos_at_r(r,mos_array)
     do m = 1, mo_tot_num
      do i = 1, mo_tot_num
       if(dabs(one_body_dm_mo_alpha(i,m,i_state)).lt.1.d-10)cycle
       contrib = mos_array(i) * mos_array(m)
       one_body_dm_mo_alpha_at_grid_points(l,k,j,i_state) += one_body_dm_mo_alpha(i,m,i_state) * contrib
       one_body_dm_mo_beta_at_grid_points(l,k,j,i_state) += one_body_dm_mo_beta(i,m,i_state) * contrib
      enddo
     enddo

    enddo
   enddo
  enddo
 enddo

END_PROVIDER 

