! compute gamma1 for the full state.

module make_gamma_module

  use bl_types
  use multifab_module
  use ml_layout_module
  use average_module

  implicit none

  private

  public :: make_gamma1bar

contains

  subroutine make_gamma1bar(mla,scal,gamma1bar,p0,dx)

    type(ml_layout), intent(in   ) :: mla
    type(multifab) , intent(in   ) :: scal(:)
    real(dp_t)     , intent(inout) :: gamma1bar(:,0:)
    real(dp_t)    ,  intent(in   ) :: p0(:,0:)
    real(dp_t)    ,  intent(in   ) :: dx(:,:)

    integer :: n,nlevs

    type(multifab) :: gamma1(mla%nlevel)

    nlevs = mla%nlevel

    do n=1,nlevs
       call multifab_build(gamma1(n), mla%la(n), 1, 0)
    end do

    call make_gamma(mla,gamma1,scal,p0,dx)
    call average(mla,gamma1,gamma1bar,dx,1)

    do n=1,nlevs
       call multifab_destroy(gamma1(n))
    end do

  end subroutine make_gamma1bar


  subroutine make_gamma(mla,gamma,scal,p0,dx)

    use bl_prof_module
    use ml_cc_restriction_module
    use multifab_fill_ghost_module
    use geometry, only: spherical

    type(ml_layout), intent(in   ) :: mla
    type(multifab) , intent(inout) :: gamma(:)
    type(multifab) , intent(in   ) :: scal(:)
    real(kind=dp_t), intent(in   ) :: p0(:,0:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)

    real(kind=dp_t), pointer:: gamp(:,:,:,:),sp(:,:,:,:)
    integer :: lo(mla%dim),hi(mla%dim)
    integer :: i,n,dm,nlevs
    integer :: ng_g, ng_s

    type(bl_prof_timer), save :: bpt

    call build(bpt, "make_gamma")

    dm = mla%dim
    nlevs = mla%nlevel

    ng_g = nghost(gamma(1))
    ng_s = nghost(scal(1))

    do n = 1, nlevs
       do i = 1, nfabs(scal(n))
          gamp => dataptr(gamma(n), i)
          sp   => dataptr(scal(n), i)
          lo = lwb(get_box(scal(n), i))
          hi = upb(get_box(scal(n), i))
          select case (dm)
          case (1)
             call make_gamma_1d(lo,hi,gamp(:,1,1,1),ng_g,sp(:,1,1,:),ng_s,p0(n,:))
          case (2)
             call make_gamma_2d(lo,hi,gamp(:,:,1,1),ng_g,sp(:,:,1,:),ng_s,p0(n,:))
          case (3)
             if (spherical .eq. 1) then
                call make_gamma_3d_sphr(lo,hi,gamp(:,:,:,1),ng_g,sp(:,:,:,:),ng_s,p0(1,:), &
                                        dx(n,:))
             else
                call make_gamma_3d(lo,hi,gamp(:,:,:,1),ng_g,sp(:,:,:,:),ng_s,p0(n,:))
             end if
          end select
       end do
    end do

    ! gamma1 has no ghost cells so we don't need to fill them
    ! the loop over nlevs must count backwards to make sure the finer grids are done first
    do n=nlevs,2,-1
       ! set level n-1 data to be the average of the level n data covering it
       call ml_cc_restriction(gamma(n-1), gamma(n), mla%mba%rr(n-1,:))
    end do

    call destroy(bpt)

  end subroutine make_gamma

  subroutine make_gamma_1d(lo,hi,gamma,ng_g,scal,ng_s,p0)

    use eos_module, only: eos, eos_input_rp
    use eos_type_module
    use network, only: nspec
    use variables, only: rho_comp, spec_comp, temp_comp, pi_comp
    use probin_module, only: use_pprime_in_tfromp

    integer         , intent(in   ) :: lo(:), hi(:), ng_g, ng_s
    real (kind=dp_t), intent(  out) :: gamma(lo(1)-ng_g:)
    real (kind=dp_t), intent(in   ) ::  scal(lo(1)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: p0(0:)

    ! local variables
    integer :: i

    integer :: pt_index(MAX_SPACEDIM)
    type (eos_t) :: eos_state

    do i = lo(1), hi(1)

       eos_state%rho   = scal(i,rho_comp)
       if (use_pprime_in_tfromp) then
          eos_state%p     = p0(i) + scal(i,pi_comp)
       else
          eos_state%p     = p0(i)
       endif
       eos_state%xn(:) = scal(i,spec_comp:spec_comp+nspec-1)/eos_state%rho
       eos_state%T     = scal(i,temp_comp)

       pt_index(:) = (/i, -1, -1/)

       ! dens, pres, and xmass are inputs
       call eos(eos_input_rp, eos_state, pt_index)

       gamma(i) = eos_state%gam1

    end do

  end subroutine make_gamma_1d

  subroutine make_gamma_2d(lo,hi,gamma,ng_g,scal,ng_s,p0)

    use eos_module, only: eos, eos_input_rp
    use eos_type_module
    use network, only: nspec
    use variables, only: rho_comp, spec_comp, temp_comp, pi_comp
    use probin_module, only: use_pprime_in_tfromp

    integer         , intent(in   ) :: lo(:), hi(:), ng_g, ng_s
    real (kind=dp_t), intent(  out) :: gamma(lo(1)-ng_g:,lo(2)-ng_g:)
    real (kind=dp_t), intent(in   ) ::  scal(lo(1)-ng_s:,lo(2)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: p0(0:)

    ! local variables
    integer :: i, j

    integer :: pt_index(MAX_SPACEDIM)
    type (eos_t) :: eos_state

    do j = lo(2), hi(2)
       do i = lo(1), hi(1)

          eos_state%rho   = scal(i,j,rho_comp)
          if (use_pprime_in_tfromp) then
             eos_state%p     = p0(j) + scal(i,j,pi_comp)
          else
             eos_state%p     = p0(j)
          endif
          eos_state%xn(:) = scal(i,j,spec_comp:spec_comp+nspec-1)/eos_state%rho
          eos_state%T     = scal(i,j,temp_comp)

          pt_index(:) = (/i, j, -1/)

          ! dens, pres, and xmass are inputs
          call eos(eos_input_rp, eos_state, pt_index)

          gamma(i,j) = eos_state%gam1

       end do
    end do

  end subroutine make_gamma_2d

  subroutine make_gamma_3d(lo,hi,gamma,ng_g,scal,ng_s,p0)

    use eos_module, only: eos, eos_input_rp
    use eos_type_module
    use network, only: nspec
    use variables, only: rho_comp, spec_comp, temp_comp, pi_comp
    use fill_3d_module
    use probin_module, only: use_pprime_in_tfromp

    integer         , intent(in   ) :: lo(:), hi(:), ng_g, ng_s
    real (kind=dp_t), intent(  out) :: gamma(lo(1)-ng_g:,lo(2)-ng_g:,lo(3)-ng_g:)
    real (kind=dp_t), intent(in   ) ::  scal(lo(1)-ng_s:,lo(2)-ng_s:,lo(3)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: p0(0:)

    ! local variables
    integer :: i, j, k

    integer :: pt_index(MAX_SPACEDIM)
    type (eos_t) :: eos_state

    !$OMP PARALLEL DO PRIVATE(i,j,k,pt_index,eos_state)
    do k = lo(3), hi(3)
       do j = lo(2), hi(2)
          do i = lo(1), hi(1)

             eos_state%rho   = scal(i,j,k,rho_comp)
             if (use_pprime_in_tfromp) then
                eos_state%p     = p0(k) + scal(i,j,k,pi_comp)
             else
                eos_state%p     = p0(k)
             endif
             eos_state%T     = scal(i,j,k,temp_comp)
             eos_state%xn(:) = scal(i,j,k,spec_comp:spec_comp+nspec-1)/eos_state%rho

             pt_index(:) = (/i, j, k/)

             ! dens, pres, and xmass are inputs
             call eos(eos_input_rp, eos_state, pt_index)

             gamma(i,j,k) = eos_state%gam1

          end do
       end do
    end do
    !$OMP END PARALLEL DO

  end subroutine make_gamma_3d

  subroutine make_gamma_3d_sphr(lo,hi,gamma,ng_g,scal,ng_s,p0,dx)

    use eos_module, only: eos, eos_input_rp
    use eos_type_module
    use network, only: nspec
    use variables, only: rho_comp, spec_comp, temp_comp, pi_comp
    use fill_3d_module
    use probin_module, only: use_pprime_in_tfromp

    integer         , intent(in   ) :: lo(:), hi(:), ng_g, ng_s
    real (kind=dp_t), intent(  out) :: gamma(lo(1)-ng_g:,lo(2)-ng_g:,lo(3)-ng_g:)
    real (kind=dp_t), intent(in   ) ::  scal(lo(1)-ng_s:,lo(2)-ng_s:,lo(3)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: p0(0:)
    real (kind=dp_t), intent(in   ) :: dx(:)

    ! local variables
    integer :: i, j, k

    real (kind=dp_t), allocatable :: p0_cart(:,:,:,:)

    integer :: pt_index(MAX_SPACEDIM)
    type (eos_t) :: eos_state

    allocate(p0_cart(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),1))
    call put_1d_array_on_cart_3d_sphr(.false.,.false.,p0,p0_cart,lo,hi,dx,0)

    !$OMP PARALLEL DO PRIVATE(i,j,k,eos_state,pt_index)
    do k = lo(3), hi(3)
       do j = lo(2), hi(2)
          do i = lo(1), hi(1)

             eos_state%rho   = scal(i,j,k,rho_comp)
             if (use_pprime_in_tfromp) then
                eos_state%p     = p0_cart(i,j,k,1) + scal(i,j,k,pi_comp)
             else
                eos_state%p     = p0_cart(i,j,k,1)
             endif
             eos_state%T     = scal(i,j,k,temp_comp)
             eos_state%xn(:) = scal(i,j,k,spec_comp:spec_comp+nspec-1)/eos_state%rho

             pt_index(:) = (/i, j, k/)

             ! dens, pres, and xmass are inputs
             call eos(eos_input_rp, eos_state, pt_index)

             gamma(i,j,k) = eos_state%gam1

          end do
       end do
    end do
    !$OMP END PARALLEL DO

    deallocate(p0_cart)

  end subroutine make_gamma_3d_sphr

end module make_gamma_module
