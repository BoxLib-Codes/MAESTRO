module init_module

  use bl_types
  use bl_constants_module
  use bc_module
  use multifab_physbc_module
  use define_bc_module
  use multifab_module
  use fill_3d_module
  use eos_module
  use variables
  use network
  use geometry
  use ml_layout_module
  use ml_restriction_module
  use multifab_fill_ghost_module

  implicit none

  private
  public :: initscalardata, initscalardata_on_level, initveldata

contains

  subroutine initscalardata(s,s0_init,p0_background,dx,bc,mla)

    type(multifab) , intent(inout) :: s(:)
    real(kind=dp_t), intent(in   ) :: s0_init(:,0:,:)
    real(kind=dp_t), intent(in   ) :: p0_background(:,0:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)
    type(bc_level) , intent(in   ) :: bc(:)
    type(ml_layout), intent(inout) :: mla

    real(kind=dp_t), pointer:: sop(:,:,:,:)
    integer :: lo(dm),hi(dm),ng
    integer :: i,n
    
    ng = s(1)%ng

    do n=1,nlevs
       do i = 1, s(n)%nboxes
          if ( multifab_remote(s(n),i) ) cycle
          sop => dataptr(s(n),i)
          lo =  lwb(get_box(s(n),i))
          hi =  upb(get_box(s(n),i))
          
          select case (dm)
          case (2)
             call bl_error('initscalardata_2d not written')
          case (3)
             if (spherical .eq. 1) then
                call initscalardata_3d_sphr(sop(:,:,:,:), lo, hi, ng, dx(n,:), &
                                            s0_init(1,:,:), p0_background(1,:))
             else
                call bl_error('initscalardata_3d not written')
             end if
          end select
       end do
    enddo

    if (nlevs .eq. 1) then

       ! fill ghost cells for two adjacent grids at the same level
       ! this includes periodic domain boundary ghost cells
       call multifab_fill_boundary(s(nlevs))

       ! fill non-periodic domain boundary ghost cells
       call multifab_physbc(s(nlevs),rho_comp,dm+rho_comp,nscal,bc(nlevs))

    else

       ! the loop over nlevs must count backwards to make sure the finer grids are done first
       do n=nlevs,2,-1

          ! set level n-1 data to be the average of the level n data covering it
          call ml_cc_restriction(s(n-1),s(n),mla%mba%rr(n-1,:))

          ! fill level n ghost cells using interpolation from level n-1 data
          ! note that multifab_fill_boundary and multifab_physbc are called for
          ! both levels n-1 and n
          call multifab_fill_ghost_cells(s(n),s(n-1),ng,mla%mba%rr(n-1,:), &
                                         bc(n-1),bc(n),1,dm+rho_comp,nscal, &
                                         fill_crse_input=.false.)

       enddo

    end if
       
  end subroutine initscalardata

  subroutine initscalardata_on_level(n,s,s0_init,p0_background,dx,bc)

    integer        , intent(in   ) :: n
    type(multifab) , intent(inout) :: s
    real(kind=dp_t), intent(in   ) :: s0_init(0:,:)
    real(kind=dp_t), intent(in   ) :: p0_background(0:)
    real(kind=dp_t), intent(in   ) :: dx(:)
    type(bc_level) , intent(in   ) :: bc

    ! local
    integer                  :: ng,i
    integer                  :: lo(dm),hi(dm)
    real(kind=dp_t), pointer :: sop(:,:,:,:)

    ng = s%ng

    do i = 1, s%nboxes
       if ( multifab_remote(s,i) ) cycle
       sop => dataptr(s,i)
       lo =  lwb(get_box(s,i))
       hi =  upb(get_box(s,i))
       select case (dm)
       case (2)
          call bl_error('initscalardata_2d not written')
       case (3)
          if (spherical .eq. 1) then
             call initscalardata_3d_sphr(sop(:,:,:,:),lo,hi,ng,dx,s0_init,p0_background)
          else
             call bl_error('initscalardata_3d not written')
          end if
       end select
    end do

    call multifab_fill_boundary(s)

    call multifab_physbc(s,rho_comp,dm+rho_comp,nscal,bc)

  end subroutine initscalardata_on_level

  subroutine initscalardata_3d_sphr(s,lo,hi,ng,dx,s0_init,p0_background)

    use probin_module, only: prob_lo, perturb_model

    integer           , intent(in   ) :: lo(:), hi(:), ng
    real (kind = dp_t), intent(inout) :: s(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:,:)  
    real (kind = dp_t), intent(in   ) :: dx(:)
    real(kind=dp_t),    intent(in   ) :: s0_init(0:,:)
    real(kind=dp_t),    intent(in   ) :: p0_background(0:)

    !     Local variables
    integer :: i, j, k, comp
    real(kind=dp_t) :: x,y,z
    real(kind=dp_t) :: dens_pert, rhoh_pert, temp_pert
    real(kind=dp_t) :: rhoX_pert(nspec), trac_pert(ntrac)
    real(kind=dp_t), allocatable :: p0_cart(:,:,:,:)

    if (perturb_model) then
       call bl_error('perturb_model not written for initscalardata_3d_sphr')
    end if

    ! initial the domain with the base state
    s = ZERO

    ! if we are spherical, we want to make sure that p0 is good, since that is
    ! what is needed for HSE.  Therefore, we will put p0 onto a cart array and
    ! then initialize h from rho, X, and p0.
    allocate(p0_cart(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),1))

    ! initialize the scalars
    call put_1d_array_on_cart_3d_sphr(.false.,.false.,s0_init(:,rho_comp), &
                                      s(:,:,:,rho_comp:),lo,hi,dx,ng,0)

    call put_1d_array_on_cart_3d_sphr(.false.,.false.,s0_init(:,temp_comp), &
                                      s(:,:,:,temp_comp:),lo,hi,dx,ng,0)

    ! initialize p0_cart
    call put_1d_array_on_cart_3d_sphr(.false.,.false.,p0_background(:), &
                                      p0_cart(:,:,:,1:),lo,hi,dx,0,0)

    ! initialize species
    do comp = spec_comp, spec_comp+nspec-1
       call put_1d_array_on_cart_3d_sphr(.false.,.false.,s0_init(:,comp), &
                                         s(:,:,:,comp:),lo,hi,dx,ng,0)
    end do

    ! initialize tracers
    do comp = trac_comp, trac_comp+ntrac-1
       call put_1d_array_on_cart_3d_sphr(.false.,.false.,s0_init(:,comp), &
                                         s(:,:,:,comp:),lo,hi,dx,ng,0)
    end do

    ! initialize (rho h) using the EOS
    do k = lo(3), hi(3)
       do j = lo(2), hi(2)
          do i = lo(1), hi(1)

             temp_eos(1) = s(i,j,k,temp_comp)
             p_eos(1) = p0_cart(i,j,k,1)
             den_eos(1) = s(i,j,k,rho_comp)
             xn_eos(1,:) = s(i,j,k,spec_comp:spec_comp+nspec-1)/den_eos(1)

             call eos(eos_input_rp, den_eos, temp_eos, &
                  npts, nspec, &
                  xn_eos, &
                  p_eos, h_eos, e_eos, &
                  cv_eos, cp_eos, xne_eos, eta_eos, pele_eos, &
                  dpdt_eos, dpdr_eos, dedt_eos, dedr_eos, &
                  dpdX_eos, dhdX_eos, &
                  gam1_eos, cs_eos, s_eos, &
                  dsdt_eos, dsdr_eos, &
                  do_diag)

             s(i,j,k,rhoh_comp) = den_eos(1)*h_eos(1)
             s(i,j,k,temp_comp) = temp_eos(1)

          enddo
       enddo
    enddo

    deallocate(p0_cart)

  end subroutine initscalardata_3d_sphr

  subroutine initveldata(u,s0_init,p0_background,dx,bc,mla)

    use mt19937_module
    
    type(multifab) , intent(inout) :: u(:)
    real(kind=dp_t), intent(in   ) :: s0_init(:,0:,:)
    real(kind=dp_t), intent(in   ) :: p0_background(:,0:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)
    type(bc_level) , intent(in   ) :: bc(:)
    type(ml_layout), intent(inout) :: mla

    real(kind=dp_t), pointer:: uop(:,:,:,:)
    integer :: lo(dm),hi(dm),ng
    integer :: i,j,k,n

    ! random numbers between -1 and 1
    real(kind=dp_t) :: alpha(3,3,3), beta(3,3,3), gamma(3,3,3)

    ! random numbers between 0 and 2*pi
    real(kind=dp_t) :: phix(3,3,3), phiy(3,3,3), phiz(3,3,3)

    ! L2 norm of k
    real(kind=dp_t) :: normk(3,3,3)

    ! random number
    real(kind=dp_t) :: rand
    
    ng = u(1)%ng

    ! load in random numbers alpha, beta, gamma, phix, phiy, and phiz
    if (dm .eq. 3 .and. spherical .eq. 1) then
       call init_genrand(20908)
       do i=1,3
          do j=1,3
             do k=1,3
                rand = genrand_real1()
                rand = 2.0d0*rand - 1.0d0
                alpha(i,j,k) = rand
                rand = genrand_real1()
                rand = 2.0d0*rand - 1.0d0
                beta(i,j,k) = rand
                rand = genrand_real1()
                rand = 2.0d0*rand - 1.0d0
                gamma(i,j,k) = rand
                rand = genrand_real1()
                rand = 2.0d0*M_PI*rand
                phix(i,j,k) = rand
                rand = genrand_real1()
                rand = 2.0d0*M_PI*rand
                phiy(i,j,k) = rand
                rand = genrand_real1()
                rand = 2.0d0*M_PI*rand
                phiz(i,j,k) = rand
             enddo
          enddo
       enddo

       ! compute the norm of k
       do i=1,3
          do j=1,3
             do k=1,3
                normk(i,j,k) = sqrt(dble(i)**2+dble(j)**2+dble(k)**2)
             enddo
          enddo
       enddo
    end if

    do n=1,nlevs

       do i = 1, u(n)%nboxes
          if ( multifab_remote(u(n),i) ) cycle
          uop => dataptr(u(n),i)
          lo =  lwb(get_box(u(n),i))
          hi =  upb(get_box(u(n),i))
          select case (dm)
          case (2)
             call bl_error('initveldata_2d not written')
          case (3)
             if (spherical .eq. 1) then
                call initveldata_3d_sphr(uop(:,:,:,:), lo, hi, ng, dx(n,:), &
                                         s0_init(1,:,:), p0_background(1,:), &
                                         alpha, beta, gamma, phix, phiy, phiz, normk)
             else
                call bl_error('initveldata_3d not written')
             end if
          end select
       end do
    
    enddo

    if (nlevs .eq. 1) then

       ! fill ghost cells for two adjacent grids at the same level
       ! this includes periodic domain boundary ghost cells
       call multifab_fill_boundary(u(nlevs))

       ! fill non-periodic domain boundary ghost cells
       call multifab_physbc(u(nlevs),1,1,dm,bc(nlevs))

    else

       ! the loop over nlevs must count backwards to make sure the finer grids are done first
       do n=nlevs,2,-1

          ! set level n-1 data to be the average of the level n data covering it
          call ml_cc_restriction(u(n-1),u(n),mla%mba%rr(n-1,:))

          ! fill level n ghost cells using interpolation from level n-1 data
          ! note that multifab_fill_boundary and multifab_physbc are called for
          ! both levels n-1 and n
          call multifab_fill_ghost_cells(u(n),u(n-1),ng,mla%mba%rr(n-1,:), &
                                         bc(n-1),bc(n),1,1,dm,fill_crse_input=.false.)
       enddo
       
    end if

  end subroutine initveldata

  ! the velocity is initialized to zero plus a perturbation which is a
  ! summation of 27 fourier modes with random amplitudes and phase
  ! shifts over a square of length "velpert_scale".  The parameter
  ! "velpert_radius" is the cutoff radius, such that the actual
  ! perturbation that gets added to the initial velocity decays to
  ! zero quickly if r > "velpert_radius", via the tanh function.
  ! The steepness of the cutoff is controlled by "velpert_steep".  The
  ! relative amplitude of the modes is controlled by
  ! "velpert_amplitude".
  subroutine initveldata_3d_sphr(u,lo,hi,ng,dx,s0_init,p0_background, &
                                 alpha,beta,gamma,phix,phiy,phiz,normk)

    use probin_module, only: prob_lo, prob_hi, &
         velpert_amplitude, velpert_radius, velpert_steep, velpert_scale

    integer, intent(in) :: lo(:), hi(:), ng
    real (kind = dp_t), intent(out) :: u(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:,:)
    real (kind = dp_t), intent(in ) :: dx(:)
    real(kind=dp_t), intent(in   ) ::    s0_init(0:,:)
    real(kind=dp_t), intent(in   ) ::    p0_background(0:)

    ! random numbers between -1 and 1
    real(kind=dp_t), intent(in) :: alpha(3,3,3), beta(3,3,3), gamma(3,3,3)

    ! random numbers between 0 and 2*pi
    real(kind=dp_t), intent(in) :: phix(3,3,3), phiy(3,3,3), phiz(3,3,3)

    ! L2 norm of k
    real(kind=dp_t), intent(in) :: normk(3,3,3)

    ! Local variables
    integer :: i, j, k
    integer :: iloc, jloc, kloc

    ! cos and sin of (2*pi*kx/L + phix), etc
    real(kind=dp_t) :: cx(3,3,3), cy(3,3,3), cz(3,3,3)
    real(kind=dp_t) :: sx(3,3,3), sy(3,3,3), sz(3,3,3)

    ! location of center of star
    real(kind=dp_t) :: xc(3)

    ! radius, or distance, to center of star
    real(kind=dp_t) :: rloc

    ! the point we're at
    real(kind=dp_t) :: xloc(3)

    ! perturbational velocity to add
    real(kind=dp_t) :: upert(3)

    ! initialize the velocity to zero everywhere
    u = ZERO

    ! define where center of star is
    ! this currently assumes the star is at the center of the domain
    xc(1) = 0.5d0*(prob_lo(1)+prob_hi(1))
    xc(2) = 0.5d0*(prob_lo(2)+prob_hi(2))
    xc(3) = 0.5d0*(prob_lo(3)+prob_hi(3))

    ! now do the big loop over all points in the domain
    do iloc = lo(1),hi(1)
       do jloc = lo(2),hi(2)
          do kloc = lo(3),hi(3)

             ! set perturbational velocity to zero
             upert = ZERO

             ! compute where we physically are
             xloc(1) = prob_lo(1) + (dble(iloc)+0.5d0)*dx(1)
             xloc(2) = prob_lo(2) + (dble(jloc)+0.5d0)*dx(2)
             xloc(3) = prob_lo(3) + (dble(kloc)+0.5d0)*dx(3)

             ! compute distance to the center of the star
             rloc = ZERO
             do i=1,3
                rloc = rloc + (xloc(i) - xc(i))**2
             enddo
             rloc = sqrt(rloc)

             ! loop over the 27 combinations of fourier components
             do i=1,3
                do j=1,3
                   do k=1,3
                      ! compute cosines and sines
                      cx(i,j,k) = cos(2.0d0*M_PI*dble(i)*xloc(1)/velpert_scale + phix(i,j,k))
                      cy(i,j,k) = cos(2.0d0*M_PI*dble(j)*xloc(2)/velpert_scale + phiy(i,j,k))
                      cz(i,j,k) = cos(2.0d0*M_PI*dble(k)*xloc(3)/velpert_scale + phiz(i,j,k))
                      sx(i,j,k) = sin(2.0d0*M_PI*dble(i)*xloc(1)/velpert_scale + phix(i,j,k))
                      sy(i,j,k) = sin(2.0d0*M_PI*dble(j)*xloc(2)/velpert_scale + phiy(i,j,k))
                      sz(i,j,k) = sin(2.0d0*M_PI*dble(k)*xloc(3)/velpert_scale + phiz(i,j,k))
                   enddo
                enddo
             enddo

             ! loop over the 27 combinations of fourier components
             do i=1,3
                do j=1,3
                   do k=1,3
                      ! compute contribution from perturbation velocity from each mode
                      upert(1) = upert(1) + &
                           (-gamma(i,j,k)*dble(j)*cx(i,j,k)*cz(i,j,k)*sy(i,j,k) &
                             +beta(i,j,k)*dble(k)*cx(i,j,k)*cy(i,j,k)*sz(i,j,k)) &
                            / normk(i,j,k)

                      upert(2) = upert(2) + &
                           (gamma(i,j,k)*dble(i)*cy(i,j,k)*cz(i,j,k)*sx(i,j,k) &
                           -alpha(i,j,k)*dble(k)*cx(i,j,k)*cy(i,j,k)*sz(i,j,k)) &
                            / normk(i,j,k)

                      upert(3) = upert(3) + &
                           ( -beta(i,j,k)*dble(i)*cy(i,j,k)*cz(i,j,k)*sx(i,j,k) &
                            +alpha(i,j,k)*dble(j)*cx(i,j,k)*cz(i,j,k)*sy(i,j,k)) &
                            / normk(i,j,k)
                   enddo
                enddo
             enddo

             ! apply the cutoff function to the perturbational velocity
             do i=1,3
                upert(i) = velpert_amplitude*upert(i) &
                     *(0.5d0+0.5d0*tanh((velpert_radius-rloc)/velpert_steep))
             enddo

             ! add perturbational velocity to background velocity
             do i=1,3
                u(iloc,jloc,kloc,i) = u(iloc,jloc,kloc,i) + upert(i)
             enddo

          enddo
       enddo
    enddo
      
  end subroutine initveldata_3d_sphr

end module init_module
