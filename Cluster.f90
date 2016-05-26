! Module for SPT cluster likelihood
! See de Haan et al 2014 for more information
! v0: 19Jun14 CR
! v1: 28Aug15
! Updated for Multi Scaling Relation Study


!include 'mkl_vsl.fi'
include 'mkl_vsl.f90'
include 'blas.f90'


module Cluster
  use CosmologyTypes
  use settings
  use CosmoTheory
  use Calculator_Cosmology
  use Likelihood_Cosmology
  use mkl_vsl
  use mkl_vsl_type
  use szclus_utils
  use tinkermass
  implicit none
  
  private
  real(mcp), parameter :: sigma_xi=1 ! this is the size of the 1 sigma scatter between <xi> .and. xi: it is unity by the definition of xi as S/N
  real(mcp), parameter :: max_bias = 3 ! the maximization bias between zeta and <xi>
  integer, parameter :: tmp_file_unit = 49
  integer, parameter :: mxarrsize = 1024
  integer, parameter:: n_samples=10000 !for MCMC
  integer, parameter :: num_mpk_k = 1000
  integer, parameter :: num_mpk_lnz = 150
  real(mcp), parameter :: mpk_k_min = 0.00005, mpk_k_max = 30
  real(mcp), dimension(0: num_mpk_k-1) :: mpk_k_arr
  real(kind = 8), dimension(n_samples) :: buffer
  real(kind = 8), parameter :: zeromean=0,sigma=1 !distribution details
  integer(kind = 4) :: errcode
  integer :: vslseed
  logical :: first_time = .true. 
  TYPE (VSL_STREAM_STATE) :: stream  

  logical :: use_clusters = .false.
  !NB: Code assumes these are ordered from 1 to MAX_NOBS
  !Order *does* matter. must match indexing in code
  integer, parameter :: OBS_SZ=1, OBS_YSZ=2, OBS_YX=3, OBS_WL=4, OBS_vd = 5, OBS_OR = 6, OBS_Lx = 7, OBS_Tx = 8, OBS_Mg =9
  
  type massfunc
     !integer nm
     !real*8 m_min,m_max
     !real*8, dimension(:), pointer ::  m_arr, z_arr
     real*8, dimension(:,:), pointer :: dn !, dndlogmdz
  end type massfunc

  type scalingreln
     !order matters here!!!
     !must match parameter file
     !SZ
     real(mcp) :: asz, bsz, csz, dsz, esz, fsz
     !X-ray
     real(mcp) :: ax, bx, cx, dx
     real(mcp) :: rho
     real(mcp) :: fnl !not exactly scaling relation, but easier to leave here for casting purposes
     !should consider moving it
     !weak lensing
     real(mcp) :: awl,bwl,cwl,dwl,ewl,fwl
     real(mcp) :: rho_wl_sz, rho_wl_x
     !YSZ
     real(mcp) :: aysz, bysz, cysz, dysz
     real(mcp) :: rho_ysz_xi, rho_ysz_sz
     !VD
!     real(mcp) :: miscthing
     real(mcp) :: avd, bvd, cvd, d0vd, dnvd 
     !OR
     real(mcp) :: aor, bor, cor, dor
     !Lx
     real(mcp) :: alx, blx, clx, dlx
     !Tx
     real(mcp) :: atx, btx, ctx, dtx
     !Mg
     real(mcp) :: amg, bmg, cmg, dmg
     !rhos , may scrap some of these
     real(mcp) :: rho_vd_sz = 0, rho_vd_yx = 0, rho_vd_wl = 0, rho_vd_or = 0, rho_vd_tx = 0, rho_vd_lx = 0, rho_vd_mg = 0
     real(mcp) :: rho_or_sz, rho_or_yx, rho_or_wl, rho_or_lx, rho_or_tx, rho_or_mg
     real(mcp) :: rho_lx_sz, rho_lx_yx, rho_lx_wl, rho_lx_tx, rho_lx_mg
     real(mcp) :: rho_tx_sz, rho_tx_yx, rho_tx_wl, rho_tx_mg
     real(mcp) :: rho_mg_sz, rho_mg_yx, rho_mg_wl
     
  end type scalingreln

  integer, parameter :: Nparam_SR = 47 !extra 21
  integer,parameter :: Nszx_SR=11,Nwl_SR=8,iwl_SR=13
  
  real(mcp), dimension(Nparam_SR), parameter :: hard_SR_min=(/ &
       0.001,0.5,-10,-10,-10,.05, & !SZ
       .001,.05,-10.,.01,& !x
       -.95,&!rho
       -1e9,&!fnl
       .001,.05,-10,-10,-10,.01,& !wl
       .02,.02,&!rho_wl
       -1e9,-1e9,-1e9,-1e9,-1e9,-1e9,&  !ysz stuff - skip
       -1e9,-1e9,-1e9,-1e9,-1e9, &    !vd just placeholders for now 
       -1e9,-1e9,-1e9,-1e9,&    !or
       -1e9,-1e9,-1e9,-1e9,&    !lx
       -1e9,-1e9,-1e9,-1e9,&    !tx
       -1e9,-1e9,-1e9,-1e9 /)   !mg
  real(mcp), dimension(Nparam_SR), parameter :: hard_SR_max=(/ &
       100d0,3d0,10d0,10d0,10d0,2d0,&!sz
       100d0,100d0,10d0,5d0,&!X
       .95d0,& !rho
       1d9,& !fnl
       100d0,100d0,10d0,10d0,10d0,5d0,&!wl
       .6d0,.6d0,&!rhowl
       1d9,1d9,1d9,1d9,1d9,1d9,&  !ysz stuff skip
       1d9,1d9,1d9,1d9,1d9,&  !vd  (just placeholders for now)
       1d9,1d9,1d9,1d9,&  !or
       1d9,1d9,1d9,1d9,&  !lx
       1d9,1d9,1d9,1d9,&  !tx
       1d9,1d9,1d9,1d9 /) !mg
  type cosmoprm
     real*8, dimension(0: num_mpk_k-1,0:num_mpk_lnz-1) :: mp_arr
     real(mcp) :: h0,w,ombh2, omch2, omb, omc
     real(mcp) :: omm, omv 
     real(mcp) :: fnl
  end type cosmoprm

  !the minimal set to check if MF needs to be regenerated
  type cosmoprm_minimal_mf
     real(mcp) :: w, omm, omv, fnl
  end type cosmoprm_minimal_mf

  type szcatalog 
     integer :: n, n2,nfield, has_ysz, has_wl, has_vd,has_or, has_Lx, has_Tx, has_Mg
     !nfield
     real*8, allocatable, dimension(:) :: field_area, field_scalefac, false_alpha,false_beta
     
     ! dim = n
     integer,allocatable,  dimension(:) :: field_index
     real*8, allocatable, dimension(:) :: da_vec, sz_vec,x_vec,z_vec,&
          logx_err_vec,z_err_vec, ysz_vec, &
          ysz_err_vec,zeta_wl_vec,logerr_zeta_wl_vec, &
          vd_vec, vd_err_vec,ngal_vec, OR_vec, OR_err_vec, Lx_vec, &
          Lx_err_vec, mg_vec, Mg_err_vec, Tx_vec, Tx_err_vec
     ! dim n x n2
     real*8, allocatable, dimension(:,:) :: r_mg, r_tx, mgr_vec, txr_vec
     real*8 :: rhoins_ysz_xi
   contains
     procedure, private ::  Catalog_Initialize
  end type szcatalog
  type szparameters
     real(mcp) ::  area
     real(mcp) :: delta
     integer :: rho_crit, grid2d
     integer :: nm,nz,nx,nsz
     real(mcp), dimension(0:mxarrsize-1) ::  m_arr, z_arr, x_arr, sz_arr, lnm_arr
     real(mcp) :: lm_min,m_min, delta_lm, delta_z, z_min,z_max,delta_sz, sz_min, sz_max
     real(mcp) :: x_min,x_max,delta_x, z_cut, m_cut, mpivot_sz, z_pivot, szthresh, szthresh_max
     real(mcp) :: wl_mpivot, wl_zpivot, wl_z_sources
     real(mcp) :: ysz_pivot
     real(mcp), dimension(0:3) :: x_central_vals, x_prior
     real(mcp), dimension(0:5) :: sz_central_vals, sz_prior
     real(mcp), dimension(0:5) :: wl_central_vals, wl_prior
     real(mcp), dimension(0:2) :: rhos_central_vals, rhos_prior
     real(mcp), dimension(0:3) :: ysz_central_vals, ysz_prior
     real(mcp), dimension(0:4) :: vd_central_vals, vd_prior
     real(mcp), dimension(0:3) :: or_central_vals, or_prior
     real(mcp), dimension(0:3) :: lx_central_vals, lx_prior
     real(mcp), dimension(0:3) :: tx_central_vals, tx_prior
     real(mcp), dimension(0:3) :: mg_central_vals, mg_prior
     real(mcp) :: version
!     real(mcp), allocatable,dimension(:,:) :: sig_rz
     contains
       procedure, private :: Parameters_Initialize
  end type szparameters

  type, extends(TCosmoCalcLikelihood) :: ClusterLikelihood
      type(szcatalog) :: catalog
      type(szparameters) :: parameters
      type(massfunc) :: mf
      type(cosmoprm) :: csm
      type(cosmoprm_minimal_mf) :: lastCSMParam
      real(mcp), dimension(0: num_mpk_lnz-1) :: mpk_z_arr
      real(mcp) :: mpk_z_min,mpk_z_max,mpk_dlnz
      logical :: do_yx, do_wl, do_ysz, do_or, do_vd, do_Lx, do_Mg, do_Tx
   contains
     procedure :: LogLike => Cluster_LnLike
     procedure :: ReadIni => Cluster_ReadIni
     procedure, private :: calculate_lnlike_mc_matrix
     procedure, private :: generate_mf
     procedure, private :: yx_calc
     procedure, private :: compute_ncluster
!     procedure, private :: compute_ncluster_vector
  end type  ClusterLikelihood


  public use_clusters,  ClusterLikelihood,  ClusterLikelihood_Add
contains
  
  subroutine ClusterLikelihood_Add(LikeList, Ini)
    class(TLikelihoodList) :: LikeList
    class(TSettingIni) :: ini
    Type(ClusterLikelihood), pointer :: this
    integer(kind=4) errcode
    integer vslseed,ij
    real(mcp) klr
    character(len=10) :: fred
    use_clusters = (Ini%Read_Logical('use_clusters',.false.))
    if (use_clusters) then 
       allocate(this)
       call this%loadParamNames(Ini%ReadFileName('cluster_paramnames'))
       call this%ReadDatasetFile(Ini%ReadFileName('cluster_dataset'))
       allocate(this%mf%dn(0:this%parameters%nm-1, 0:this%parameters%nz-1))
       this%LikelihoodType = 'Clusters'
       this%name='cluster'
       this%needs_background_functions = .true.
       this%needs_powerspectra = .true.
       this%version = 'v1.0'
       this%needs_nonlinear_pk = .false.
       this%speed = -5
       call LikeList%Add(this)
       if (first_time) then 
          first_time = .false.
          !initialize
          !          vslseed=777
          call system_clock(count=ij)
          ij = mod(ij , 31328)
          call date_and_time(time=fred)
          read (fred,'(e10.3)') klr
          vslseed = mod(int(klr*1000), 30081)
          errcode=vslnewstream( stream, VSL_BRNG_MT19937,  vslseed )
          
       endif
    endif
  end subroutine ClusterLikelihood_Add

  subroutine Cluster_ReadIni(this, Ini)
    implicit none
    class(ClusterLikelihood) this
    class(TSettingIni) :: Ini
    character(LEN=:), allocatable :: cluster_catalog_file, cluster_parameter_file
    Type(TTextFile) :: F
    real(mcp) z_max,dlnk
    integer i

    cluster_catalog_file = Ini%ReadFileName('cluster_catalog_file')    
    call this%catalog%Catalog_Initialize(cluster_catalog_file)

    cluster_parameter_file = Ini%ReadFileName('cluster_parameter_file')
    call F%Open(cluster_parameter_file)
    call this%parameters%Parameters_Initialize(F)
    call F%close()
    this%lastCSMParam%w=logZero
    this%lastCSMParam%omm=logZero
    this%lastCSMParam%omv=logZero
    this%lastCSMParam%fnl=logZero
    !arguments
    this%do_yx = Ini%Read_Logical('do_yx',.false.)
    this%do_wl  = Ini%Read_Logical('do_wl',.false.)
    if (this%catalog%has_wl .ne. 1 .and. this%do_wl) then
       print*,'Warning: Requested weak lensing, but no weak lensing info in catalog file'
       this%do_wl  = .false.
    endif
    this%do_ysz = Ini%Read_Logical('do_ysz',.false.)
    if (this%catalog%has_ysz .ne. 1 .and. this%do_ysz) then
       print*,'Warning: Requested Ysz, but no Ysz info in catalog file'
       this%do_ysz  = .false.
    endif
    !if (this%do_ysz) then
    !   call mpistop('ysz not fully implemented')
    !endif
    this%do_vd = Ini%Read_Logical('do_vd',.false.)
    if(this%catalog%has_vd .ne. 1 .and. this%do_vd) then
       print*,'Warning: Requested Velocity dispersions, but no velocity disperion info in catalog file'
       this%do_vd = .false.
    endif
    this%do_OR = Ini%Read_Logical('do_OR',.false.)
    if(this%catalog%has_OR .ne. 1 .and. this%do_OR) then
       print*,'Warning: Requested optical richness, but no optical richness info in catalog file'
       this%do_OR = .false.
    endif
    this%do_Lx = Ini%Read_Logical('do_Lx',.false.)
    if(this%catalog%has_Lx .ne. 1 .and. this%do_Lx) then
       print*,'Warning: Requested X-ray Luminosity, but no X-ray Luminosity info in catalog file'
       this%do_Lx = .false.
    endif
    this%do_Tx = Ini%Read_Logical('do_Tx',.false.)
    if(this%catalog%has_Tx .ne. 1 .and. this%do_Tx) then
       print*,'Warning: Requested X-ray Temperature, but no X-ray Temperature info in catalog file'
       this%do_Tx = .false.
    endif
    this%do_Mg = Ini%Read_Logical('do_Mg',.false.)
    if(this%catalog%has_Mg .ne. 1 .and. this%do_Mg) then
       print*,'Warning: Requested X-ray Gas Mass, but no X-ray Gas Mass info in catalog file'
       this%do_Mg = .false.
    endif
     if((this%do_yx .and. this%do_Lx) .or. (this%do_yx .and. this%do_Tx) .or. (this%do_yx .and. this%do_Mg)) then
       call mpistop('multiple X-ray observables not fully implemented')
       print*,'what'
    endif
    !setup stuff for interpolation

    z_max = this%parameters%z_max+0.01
    this%max_z = z_max
    this%num_z = num_mpk_lnz 
    !miscellany
    dlnk = log(mpk_k_max/mpk_k_min)/(num_mpk_k-1)

    do i=0,num_mpk_k-1
       mpk_k_arr(i)=mpk_k_min * exp( i*dlnk)
    enddo
    
    
    this%mpk_dlnz=log(z_max+1)/ (num_mpk_lnz-1)
    do i=0,num_mpk_lnz-1
       this%mpk_z_arr(i) = exp(this%mpk_dlnz*i)-1._mcp
    enddo
    this%mpk_z_arr(0) = 0
    this%mpk_z_min = 0
    this%mpk_z_arr(num_mpk_lnz-1) = z_max
    this%mpk_z_max = z_max

  end subroutine Cluster_ReadIni
  
  subroutine Parameters_Initialize(this,F)
    implicit none
    Class(szparameters) :: this
    Type(TTextFile) :: F
    integer i
       
    read (F%unit,*) this%area
    read (F%unit,*) this%delta
    read (F%unit,*) this%rho_crit
    read (F%unit,*) this%grid2d
    read (F%unit,*) this%nm
    if (this%nm .gt. mxarrsize) then
       write(*,*) 'Error with nm size'
       call DoStop
    end if
    this%m_arr(:)=0
    do i=0,this%nm-1
       read (F%unit,*) this%m_arr(i)
    end do
    this%lnm_arr(:)=0
    this%lnm_arr(0:this%nm-1) = log(this%m_arr(0:this%nm-1))
    read (F%unit,*) this%lm_min
    read (F%unit,*) this%m_min
    read (F%unit,*) this%delta_lm
    read (F%unit,*) this%nz
    if (this%nz .gt. mxarrsize) then
       write(*,*) 'Error with nz size'
       call DoStop
    end if
    this%z_arr=0
    do i=0,this%nz-1
       read (F%unit,*) this%z_arr(i)
    end do
    read (F%unit,*) this%delta_z
    read (F%unit,*) this%z_min
    read (F%unit,*) this%z_max
    read (F%unit,*) this%nsz
    if (this%nsz .gt. mxarrsize) then
       write(*,*) 'Error with nsz size'
       call DoStop
    end if
    this%sz_arr=0
    do i=0,this%nsz-1
       read (F%unit,*) this%sz_arr(i)
    end do
    read (F%unit,*) this%delta_sz
    read (F%unit,*) this%sz_min
    read (F%unit,*) this%sz_max
    read (F%unit,*) this%nx
    if (this%nx .gt. mxarrsize) then
       write(*,*) 'Error with nm size'
       call DoStop
    end if
    this%x_arr=0
    do i=0,this%nx-1
       read (F%unit,*) this%x_arr(i)
    end do
    read (F%unit,*) this%delta_x
    read (F%unit,*) this%x_min
    read (F%unit,*) this%x_max
    do i=0,3
       read (F%unit,*) this%x_central_vals(i)
    end do
    do i=0,5
       read (F%unit,*) this%sz_central_vals(i)
    end do
    do i=0,5
       read (F%unit,*) this%wl_central_vals(i)
    end do
    do i=0,2
       read (F%unit,*) this%rhos_central_vals(i)
    end do
    do i=0,3
       read (F%unit,*) this%x_prior(i)
    end do
    do i=0,5
       read (F%unit,*) this%sz_prior(i)
    end do
    do i=0,5
       read (F%unit,*) this%wl_prior(i)
    end do
    do i=0,2
       read (F%unit,*) this%rhos_prior(i)
    end do
    read (F%unit,*) this%z_cut
    read (F%unit,*) this%m_cut
    read (F%unit,*) this%mpivot_sz
    read (F%unit,*) this%z_pivot 
    read (F%unit,*) this%szthresh
    read (F%unit,*) this%wl_mpivot
    read (F%unit,*) this%wl_zpivot
    read (F%unit,*) this%wl_z_sources
    read (F%unit,*) this%version      
    if(this%version .gt. 2) then
         read (F%unit,*) this%szthresh_max
    else
         this%szthresh_max = 100
    endif
    if(this%version .gt. 1) then
       do i=0,4
          read (F%unit,*) this%vd_central_vals(i)
       end do
       do i=0,4
          read (F%unit,*) this%vd_prior(i)
       end do
    endif
    
 end subroutine Parameters_Initialize

  subroutine Catalog_Initialize(this,aname)
    implicit none
    Class(szcatalog) :: this
    character(LEN=*), intent(IN) :: aname
    integer*8 recl,posn
    integer*4 version,itmp1,itmp2,itmp3,itmp4,itmp5,itmp6
    call OpenReadBinaryStreamFile(aname,tmp_file_unit)
    posn=1
    read(tmp_file_unit,pos=posn)version,this%n,this%n2,this%nfield, this%has_ysz, this%has_wl
    posn=posn+4_8 * 6
    if (version .ge. 2) then 
       read(tmp_file_unit,pos=posn)this%has_vd
       posn=posn+4_8
    endif
    if (version .ne. 1 .and. version .ne. 2 .and. version .ne. 3) then
       call mpistop('Catalog_initialize: Unsupported version number')
    endif

    if (feedback > 1) then
       print*,'basics: ',version,this%n,this%n2,this%nfield, this%has_ysz, this%has_wl, this%has_vd
    endif
    !do allocates
    allocate(this%field_area(this%nfield),this%field_scalefac(this%nfield),&
         this%false_alpha(this%nfield),this%false_beta(this%nfield))
    allocate(this%field_index(this%n),this%x_vec(this%n),this%sz_vec(this%n),&
         this%da_vec(this%n),this%z_vec(this%n),&
         this%logx_err_vec(this%n),this%z_err_vec(this%n))
    allocate(this%r_mg(this%n2,this%n),this%r_tx(this%n2,this%n),&
         this%mgr_vec(this%n2,this%n),this%txr_vec(this%n2,this%n))
    read(tmp_file_unit, pos=posn)this%field_area
    posn=posn + 8_8 * this%nfield
    read(tmp_file_unit, pos=posn)this%field_scalefac
    posn=posn + 8_8 * this%nfield
    read(tmp_file_unit, pos=posn)this%false_alpha
    posn=posn + 8_8 * this%nfield
    read(tmp_file_unit, pos=posn)this%false_beta
    posn=posn + 8_8 * this%nfield
    read(tmp_file_unit,pos=posn) this%field_index
    !IDL is 0 indexed, increment by 1
    this%field_index=this%field_index+1
    posn=posn + 4_8 * this%n
    read(tmp_file_unit,pos=posn) this%da_vec
    posn=posn + 8_8 * this%n
    read(tmp_file_unit,pos=posn) this%sz_vec
    posn=posn + 8_8 * this%n
    read(tmp_file_unit,pos=posn) this%x_vec
    posn=posn + 8_8 * this%n
    read(tmp_file_unit,pos=posn) this%logx_err_vec
    posn=posn + 8_8 * this%n
    read(tmp_file_unit,pos=posn) this%z_vec
    posn=posn + 8_8 * this%n
    read(tmp_file_unit,pos=posn) this%z_err_vec
    posn=posn + 8_8 * this%n
    if (this%has_ysz) then
       allocate(this%ysz_vec(this%n),this%ysz_err_vec(this%n))
       read(tmp_file_unit,pos=posn) this%ysz_vec
       posn=posn + 8_8 * this%n
       read(tmp_file_unit,pos=posn) this%ysz_err_vec
       posn=posn + 8_8 * this%n
    endif
    if (this%has_wl) then
       allocate(this%zeta_wl_vec(this%n),this%logerr_zeta_wl_vec(this%n))
       read(tmp_file_unit,pos=posn) this%zeta_wl_vec
       posn=posn + 8_8 * this%n
       read(tmp_file_unit,pos=posn) this%logerr_zeta_wl_vec
       posn=posn + 8_8 * this%n
    endif
  
    if (this%has_OR) then
       allocate(this%OR_vec(this%n), this%OR_err_vec(this%n))
       read(tmp_file_unit,pos=posn) this%OR_vec
       posn=posn +8_8 * this%n
       read(tmp_file_unit,pos=posn) this%OR_err_vec
       posn=posn + 8_8 * this%n
    endif
    if (this%has_Lx) then
       allocate(this%Lx_vec(this%n), this%Lx_err_vec(this%n))
       read(tmp_file_unit,pos=posn) this%Lx_vec
       posn=posn +8_8 * this%n
       read(tmp_file_unit,pos=posn) this%Lx_err_vec
       posn=posn + 8_8 * this%n
    endif
    if (this%has_Tx) then
       allocate(this%Tx_vec(this%n), this%Tx_err_vec(this%n))
       read(tmp_file_unit,pos=posn) this%Tx_vec
       posn=posn +8_8 * this%n
       read(tmp_file_unit,pos=posn) this%Tx_err_vec
       posn=posn + 8_8 * this%n
    endif
    if (this%has_Mg) then
       allocate(this%Mg_vec(this%n), this%Mg_err_vec(this%n))
       read(tmp_file_unit,pos=posn) this%Mg_vec
       posn=posn +8_8 * this%n
       read(tmp_file_unit,pos=posn) this%Mg_err_vec
       posn=posn + 8_8 * this%n
    endif
    read(tmp_file_unit,pos=posn) this%r_mg
    posn=posn + 8_8 * this%n*this%n2
    read(tmp_file_unit,pos=posn) this%r_tx
    posn=posn + 8_8 * this%n*this%n2
    read(tmp_file_unit,pos=posn) this%mgr_vec
    posn=posn + 8_8 * this%n*this%n2
    read(tmp_file_unit,pos=posn) this%txr_vec
    posn=posn + 8_8 * this%n*this%n2
    if (this%has_vd) then
       allocate(this%vd_vec(this%n), this%vd_err_vec(this%n), this%ngal_vec(this%n))
       read(tmp_file_unit,pos=posn) this%vd_vec
       posn=posn +8_8 * this%n
       read(tmp_file_unit,pos=posn) this%vd_err_vec
       posn=posn + 8_8 * this%n
       read(tmp_file_unit,pos=posn) this%ngal_vec
       posn=posn+ 8_8 * this%n
    endif
    if( version .ge. 3) then
       read(tmp_file_unit,pos=posn) this%rhoins_ysz_xi
       posn = posn + 8_8
    endif
    close(tmp_file_unit)
  end subroutine Catalog_Initialize
    
  function Cluster_LnLike(this, CMB, Theory, DataParams)
    Class(ClusterLikelihood) :: this
    Class(CMBParams) CMB
    Class(TCosmoTheoryPredictions),target  :: Theory
    real(mcp) :: DataParams(:)
    type(scalingreln) :: SR
    integer i,j,l,fid
    integer fail
    real(mcp) :: Cluster_LnLike
    type(cosmoprm) :: csm
    real(mcp) time
    real*8 temp
    !catalog already loaded

!call Timer('Up to cluster')
    !not sure about next lines!
    do j=0, num_mpk_lnz-1
       do i=0,num_mpk_k-1
          csm%mp_arr(i,j) = Theory%MPK%PowerAt(mpk_k_arr(i),this%mpk_z_arr(j))
       enddo
    enddo
    ! value of a is the length of the side of a cube
    mean_correl = 0
    do m = 0, num_mpk_k-1
    	dk = mpk_k_arr(m+1) - mpk_k_arr(m)
    	mean_correl = mean_correl+dk*(((sin((mpk_k_arr(m)+mpk_k_arr(m+1))*0.5*a)).^2/((mpk_k_arr(m)+mpk_k_arr(m+1))*a).^2)*(csm%mp_arr(m,0) +csm%mp_arr(m+1,0))*0.5)/(((mpk_k_arr(m+1)+mpk_k_arr(m))/2.).^4 * a.^6)
    enddo
    mean_correl = (mean_correl)/(2*3.14*3.14)
    



! calculate the mean correaltion function

    if (feedback > 4) then
       fid=33
       open(unit=fid,file='header.txt',action='write',status='replace')
       write(fid,*)num_mpk_k,num_mpk_lnz
       close(fid)
       call OpenWriteBinaryFile('vectormpks',fid,8_8 )
       do l=1,num_mpk_k
          temp=mpk_k_arr(l-1)
          write(fid,rec=l)temp
       enddo
       print*,'k:',mpk_k_arr(1:3)
       do l=1,num_mpk_lnz
          temp=this%mpk_z_arr(l-1)
          write(fid,rec=l+num_mpk_k)temp
       enddo
       print*,'z:',this%mpk_z_arr(1:3)
       l=num_mpk_lnz+num_mpk_k
       do j=0, num_mpk_lnz-1
          do i=0,num_mpk_k-1
             l=l+1
             temp=csm%mp_arr(i,j)
             write(fid,rec=l)temp
          enddo
       enddo
       print*,'mpk:',csm%mp_arr(1,1),csm%mp_arr(2,1)
       close(fid)
       
    endif

    if (CMB%omk .ne. 0) then
       call mpistop('Cluster code is not set up for non-zero curvature')
    endif

    csm%ombh2 = CMB%ombh2
    csm%omch2 = CMB%omch2
    csm%omv = CMB%omv
    csm%w = CMB%w
    csm%h0 = CMB%H0
    csm%omb =  csm%ombh2 /(csm%h0/100.)**2
    csm%omc =  csm%omch2 /(csm%h0/100.)**2
    csm%omm = 1.d0 - CMB%omv 

    !next set sr
    !Better have the right order!!!
    SR = transfer(DataParams,SR)
    !because I eventually want to move fnl into CSM, but at the moment the simplest code is to throw it into SR for now.
    csm%fnl = SR.fnl
    !structs set up
 !   call Timer('cluster prep')
    !generate mass function
    call this%generate_mf(csm)
  !  call Timer('cluster mf')
       
       !calculate log likelihood
    Cluster_LnLike = this%calculate_lnlike_mc_matrix(csm,SR,fail)
   ! call Timer('cluster like')
    if (fail .eq. 1)  then 
       Cluster_LnLike=  logZero
    endif
    
    if(feedback>1) write(*,*) trim(this%name)//' Cluster likelihood = ', Cluster_LnLike
    
  end function Cluster_LnLike
  




!------------------------------------------------------------------------------
! NAME:
!       GENERATE_MF
!
! PURPOSE:
!       TAKE A csm (COSMOLOGY) STRUCTURE AND RETURN A DN/DLOGMDZ (MASS FUNCTION)
!
! NOTES:
! 	mf (Mass Function) is a structure containing:
! 	- mf.nm (number of elements in mass vector)
! 	- mf.m_min (minimum mass value)
! 	- mf.m_max (maximum mass value)
! 	- mf.m_arr (mass vector)
! 	- mf.nz (number of elements in redshift vector)
! 	- mf.z_min (minimum redshift value)
! 	- mf.z_max (maximum redshift value)
! 	- mf.z_arr (redshift vector)
! 	- mf.dndlogmdz (dn/dlog10(m)/dz array, per volume)
! 	- mf.dn (dn array, expected number counts per given sky area)
! 
!     - Note all masses are measured in units of Msun h**-1
!
! REVISION HISTORY:
!   CR: based on IDL code on 19/6/2014
!------------------------------------

  subroutine GENERATE_MF(this,csm)
    implicit none
    type(cosmoprm) :: csm
    Class(ClusterLikelihood) :: this
    real*8 :: rho_back, z, new_delta2, sigl,sigh
    integer i, sig_kcut,j,iz0
    real*8 :: lnz,ilnz,f
    real*8, dimension(0:this%parameters%nm-1) :: dsdm_arr, sig_arr, rm_arr,&
         growthsig_arr, growthdsdm_arr, fsig, r_arr, g1,sig_0,prefactor,tmp_nm,loc_sig_rz
    real*8, dimension(0:this%parameters%nm-1, 0:this%parameters%nz-1) ::  dn1, sig_rz,DNIDL
    real*8, dimension(0:this%parameters%nz-1):: new_delta
    real*8 :: cvol,zmax
    real*8, parameter ::  cH0 = 2997.92458
    real*8 :: domega,dlm, rm, growth_fact, var1, mfm0
    real*8 :: dndmdz, dz, int_dz, da_calc0,s8, dndlogmdz
    integer :: int_z_steps,fail,max_int_z_steps
    real*8, allocatable, dimension(:) :: int_z_arr, da_int
    real*8, dimension(0:num_mpk_k-1) :: kr, window,this_mp,sinkr,coskr
    real*8 :: delta_k
    real*8, dimension(1) :: t1,t2
    real*8, external ::ddot
    integer fid
    fid=12
    !do we need to do anything?
    if (csm%w == this%lastCSMParam%w .and. &
         csm%omm == this%lastCSMParam%omm .and. &
         csm%omv == this%lastCSMParam%omv .and. &
         csm%fnl == this%lastCSMParam%fnl ) &
         return
    this%lastCSMParam%w=csm%w
    this%lastCSMParam%omm=csm%omm
    this%lastCSMParam%omv=csm%omv
    this%lastCSMParam%fnl=csm%fnl
    !ok onto real work

    !zero it out
    sig_rz(:,:) = 0.0
    domega = this%parameters%area * (PI/ 180d0)**2
    rho_back = 2.77536627e11*(csm%omb+csm%omc)
    this%mf%dn(:,:)=0
    dz=this%parameters%z_arr(1)-this%parameters%z_arr(0)
    dlm=log(this%parameters%m_arr(1) / this%parameters%m_arr(0))
    delta_k = log(mpk_k_arr(1) / mpk_k_arr(0))
    
    !calculate comoving volume element
    int_dz=dz/10.
    zmax = this%parameters%z_arr(this%parameters%nz-1)
    max_int_z_steps=NINT(zmax/int_dz)+1
    allocate(int_z_arr(max_int_z_steps),da_int(max_int_z_steps))
    do i=1,max_int_z_steps
       int_z_arr(i)=1d0+(i-1)*int_dz
    end do
    da_int(:)=1.d0/sqrt(csm%omm*(int_z_arr(:))**3 + csm%omv*(int_z_arr(:))**(3d0+3d0*csm%w))


!    rm_arr = (this%parameters%m_arr * (0.75d0/Pi/rho_back))**(1.d0/3.d0)
    call vdcbrt(this%parameters%nm,(this%parameters%m_arr * (0.75d0/Pi/rho_back)),rm_arr)
    prefactor = sqrt(4.5d0 * delta_k) / (Pi * rm_arr(:) * rm_arr(:))

    new_delta(:)=this%parameters%delta
    if (this%parameters%rho_crit .eq. 1) &
         new_delta(:) = this%parameters%delta * (1d0 + csm%omv/csm%omm *(1d0+this%parameters%z_arr(:))**(3d0*csm%w))
#ifndef NOOMPMF 
    !$OMP PARALLEL DO DEFAULT(NONE),SCHEDULE(GUIDED),&
    !$OMP    PRIVATE(i,lnz,ilnz,iz0,f,this_mp,j,kr,coskr,sinkr,window,loc_sig_rz,tmp_nm,z,growthdsdm_arr,fsig,int_z_steps,cvol,da_calc0,dndmdz,dndlogmdz),&
    !$OMP    SHARED(this,mpk_k_arr,rm_arr,prefactor,sig_rz,new_delta,int_dz,int_z_arr,da_int,csm,domega,rho_back,dz,dlm)
#endif
    do i=0,this%parameters%nz-1
       !we're going to use linear interpolation in logz space
       lnz = log(this%parameters%z_arr(i)+1)
       ilnz = lnz / this%mpk_dlnz
       iz0 = floor(ilnz)
       f = ilnz-iz0
       this_mp = (1-f)*csm%mp_arr(:,iz0) + f*csm%mp_arr(:,iz0+1) 
       !now will be this_mp / k 
       this_mp = this_mp(:) / mpk_k_arr(:) 
       do j=0,this%parameters%nm-1
          kr(:)=mpk_k_arr(:)* rm_arr(j)
          call vdsincos(num_mpk_k,kr,sinkr,coskr)
          call vddiv(num_mpk_k,sinkr,kr,window) !window is now sin(kr)/kr
          call vdsub(num_mpk_k,window,coskr,sinkr) !sinkr is now sinkr/kr - coskr
          call vdsqr(num_mpk_k,sinkr,window) !end up with same old window
          loc_sig_rz(j) = ddot(num_mpk_k,this_mp,1,window,1)
       enddo
       call vdsqrt(this%parameters%nm,loc_sig_rz,tmp_nm)
       call vdmul(this%parameters%nm,tmp_nm,prefactor,sig_rz(:,i) )

       !Calculate dndm via the Tinker mass function
       z = this%parameters%z_arr(i)
       
       call deriv(this%parameters%m_arr,sig_rz(:,i),growthdsdm_arr,this%parameters%nm)
       call tinker_f_sigma(sig_rz(:,i),this%parameters%nm,z,new_delta(i),fsig)

       !!calculate comoving volume element
       int_z_steps=NINT(z/int_dz)+1
       da_calc0=dint_tabulated_reg(int_z_arr(1:int_z_steps),da_int(1:int_z_steps),int_z_steps)
      
       cvol = (da_calc0/(1d0+z))**2/(sqrt(csm%omm*(1d0+z)**3 + csm%omv*(1d0+z)**(3d0+3d0*csm%w)))
       cvol = cvol * (1d0+z)**2 * cH0**3

       do j=0,this%parameters%nm-1 
          if (fsig(j) .ne. 0) then
             if (log(-1d0*growthdsdm_arr(j) * fsig(j) * rho_back / sig_rz(j,i) )- this%parameters%lnm_arr(j) .ge. -708d0) then
                
                dndmdz = -1d0*fsig(j)*rho_back/this%parameters%m_arr(j)/&
                     sig_rz(j,i)*growthdsdm_arr(j)
                !Convert to dn/dlogM:
                dndlogmdz = dndmdz * this%parameters%m_arr(j) 
                this%mf%dn(j,i) = dndlogmdz * cvol *domega *dlm *dz
                
             endif
          endif
       enddo
    enddo
#ifndef NOOMPMF
  !$OMP END PARALLEL DO
#endif
    print*,'m_arr:',this%parameters%m_arr(1:3)
    print*,'z_arr:',this%parameters%z_arr(1:3)
    print*,'dn:',this%mf%dn(1:3,1:3)


  !apply semi-analytic non-gaussian approximation
    if (csm%fnl .ne. 0) then 
       print*,'in fnl loop'
       !D08
       dn1(:,:)=0
       !now do it for z=0
       lnz = 0

       do j=0,this%parameters%nm-1
          kr(:)=mpk_k_arr(:)* rm_arr(j)
          window(:) = (sin(kr(:))/kr(:) - cos(kr(:)))
          window(:) = window(:) * window(:)
          sig_0(j)= sqrt( 4.5 * delta_k * sum(this_mp(:)*window(:)) ) / (Pi * rm_arr(j) * rm_arr(j))

       enddo
       kr(:)=mpk_k_arr(:)*8
       window(:) = (sin(kr(:))/kr(:) - cos(kr(:)))
       window(:) = window(:) * window(:)
       s8= sqrt( 4.5 * delta_k * sum(this_mp(:)*window(:)) ) / (Pi *64d0)

       do i=0,this%parameters%nz-1 
          z=this%parameters%z_arr(i)
          !rm_arr previously defined
          do j=0,this%parameters%nm-1 
             mfm0=1.3d-4*csm%fnl*s8*sig_rz(j,i)**(-2)+1d0
             var1 = 1.4d-4*(abs(csm%fnl)*s8)**0.8 / sig_rz(j,i)
             r_arr(:)=this%parameters%m_arr(j)/this%parameters%m_arr(:)
             g1=exp(-0.5*(r_arr(:)-mfm0)**2/var1)            
             dn1(j,i)=sum(g1(:)*this%mf%dn(:,i))/sum(g1(:))
          end do
       enddo
       this%mf%dn(:,:)=dn1(:,:)
    endif
!call OpenReadbinaryStreamFile('liketest/dn.bin',90)
!do i=0,600
!read(90)DNIDL(i,:)
!enddo
!close(90)
!this%mf%dn(:,:)=DNIDL(:,:)
    deallocate(int_z_arr,da_int)
  end subroutine GENERATE_MF

function CALCULATE_LNLIKE_MC_MATRIX(this,csm,SR,fail, mean_correl)
  implicit none
  type(cosmoprm) :: csm
  type(scalingreln) :: SR , thisSR
  Class(ClusterLikelihood) :: this
  real(mcp) CALCULATE_LNLIKE_MC_MATRIX
  integer, intent(out) :: fail
  real(mcp) delta_sz, delta_z, delta_lnm,delta
  real(mcp), dimension(0:this%parameters% nz-1) :: da_arr, ez_arr
  real(mcp) total_expected, total_area,this_nclust,this_nclust2
  real(mcp), dimension(0:this%catalog%n) :: ez_vec, da_vec,z_vec,ez_vec2,da_vec2
  real(mcp), dimension(Nparam_SR) :: input_vec
  real(mcp) :: data_lnlike,prior_lnlike,total_clust_lnlike
  real(mcp), dimension(this%catalog%n) :: data_lnlike_vec
  integer :: iclust,i,iz1
  integer(kind=4) errcode
  real(mcp) :: z, z_index,ez,da
  real(mcp) :: xi, det_obs_cov
  !interpolate scratch
  real(mcp), dimension(1) :: tmp1,tmp2
  real(mcp), dimension(n_samples) :: avxi_samples, zeta_samples, ysz_samples, vd_samples, or_samples, lx_samples, tx_samples, mg_samples,counter = 0
  real(mcp) :: alpha,beta
  integer, parameter :: MAXNZETA=5000
  real(mcp), dimension(MAXNZETA) :: pref_zeta,pref_zeta_boost,pref_int
  real(mcp), parameter :: delta_zeta = 0.01
  real(mcp) :: prefactor
  integer :: nzeta, iobs,jobs,n_observables
  integer, parameter :: MAX_NOBS = 9
  integer :: obs_type(MAX_NOBS) 
  real(mcp), dimension(2,2) :: testmat ! test matrix
  real(mcp), dimension(MAX_NOBS) :: cov_index,obscov_index
  real(mcp), dimension(MAX_NOBS,MAX_NOBS) :: covar, obs_covar, rho_matrix
  real(mcp), dimension(n_samples,MAX_NOBS) :: lnM_obs
  real(mcp) :: t2, t_sig, t1(n_samples), t0(n_samples), t_mu(n_samples), t_a(n_samples),dndlnmdz_samples(n_samples),dndlnmdz_samples2(n_samples)
  real(mcp) :: ez_pivot, da_pivot
  real(mcp) :: zeta_sr, zeta_wl,zeta_wl_logerr,z_pivot_index, field_scaling_factor
  real(mcp), dimension(2,2) :: u_matrix,Cxx,Cyy ! matrix to transform from diagonal basis to xi, ysz basis
  real(mcp), dimension(2,n_samples) :: x_matrix, y_matrix
  real(mcp) :: rhoins_ysz_xi,norm1,norm2 , outdelta = 500 , indelta = 200 
  real(mcp), dimension(n_samples) :: buffer1, buffer2
  real(mcp) :: covar1 , covar2 , cova, cov12, sig1, sig2  ! entries of the diagonalized covar matrix between ysz and xi
  real(mcp), dimension(100) :: int_vec
  real(mcp), dimension(n_samples) :: m200c , m500c ,m500,m500cf,m500cfull,m500err_vec1,m500err_vec2
  real(mcp) :: min_m200, max_m200, maxvalue,minvalue
  integer :: ncoarse,nfine, j
  real*8 scratch1(100-1), scratch2((100-1)*DF_PP_CUBIC)
  integer :: default = 1 , incrit = 1 , outcrit = 1 
  real(mcp), dimension(this%parameters%nm) :: dndlnmdz
  real(mcp) :: like
  real(mcp),dimension(21,16) :: mtest, mref
  real(mcp) :: ztest, failsum
  real(mcp) :: start,finish
  logical :: doxi
  integer fid

! == Defaults  ==
  fail = 0
  failsum = 0
  covar(:,:)=0
  obs_covar(:,:)=0
  !only implementing do_fieldscaling=2
  !

  !init stuff
  do i=1,MAXNZETA
     pref_zeta(i) = (5+i) * delta_zeta
  enddo
  where(pref_zeta > 2)
     pref_zeta_boost = sqrt(pref_zeta*pref_zeta + max_bias)
     ! B11 "placeholder" de-maximization boosting
  elsewhere
     pref_zeta_boost = pref_zeta
  endwhere
 
  !Obscov is covariance matrix for observables, cov is covariance matrix for lnM
  cov_index(OBS_SZ) = SR%fsz/SR%bsz
  obscov_index(OBS_SZ) = SR%fsz
  cov_index(OBS_YSZ) = SR%dysz*SR%bysz
  obscov_index(OBS_YSZ) = SR%dysz
  cov_index(OBS_YX) = SR%dx*SR%bx
  obscov_index(OBS_YX) = SR%dx
  cov_index(OBS_WL) = SR%fwl
  obscov_index(OBS_WL) = SR%fwl
  cov_index(OBS_VD) = 0
  obscov_index(OBS_VD) = 0 
  cov_index(OBS_OR) = SR%dor*SR%bor
  obscov_index(OBS_OR) = SR%dor
  cov_index(OBS_LX) = SR%dlx*SR%blx
  obscov_index(OBS_LX) = SR%dlx
  cov_index(OBS_TX) = SR%dtx*SR%btx
  obscov_index(OBS_TX) = SR%dtx
  cov_index(OBS_mg) = SR%dmg*SR%bmg
  obscov_index(OBS_mg) = SR%dmg

! consider just writing this to param file as matrix
  rho_matrix(:,:) = 0
! triangular matrix of correlation values
  rho_matrix(OBS_SZ,OBS_YSZ) = SR%rho_ysz_sz   
  rho_matrix(OBS_SZ,OBS_YX) = SR%rho
  rho_matrix(OBS_SZ,OBS_WL) = SR%rho_wl_sz
  rho_matrix(OBS_SZ,OBS_VD) = SR%rho_vd_sz
  rho_matrix(OBS_SZ,OBS_OR) = SR%rho_or_sz
  rho_matrix(OBS_SZ,OBS_LX) = SR%rho_lx_sz
  rho_matrix(OBS_SZ,OBS_TX) = SR%rho_tx_sz
  rho_matrix(OBS_SZ,OBS_MG) = SR%rho_mg_sz
  rho_matrix(OBS_YSZ,OBS_YX) = SR%rho
  rho_matrix(OBS_YSZ,OBS_WL) = SR%rho_wl_sz
  rho_matrix(OBS_YSZ,OBS_VD) = SR%rho_vd_sz
  rho_matrix(OBS_YSZ,OBS_OR) = SR%rho_or_sz
  rho_matrix(OBS_YSZ,OBS_LX) = SR%rho_lx_sz
  rho_matrix(OBS_YSZ,OBS_TX) = SR%rho_tx_sz
  rho_matrix(OBS_YSZ,OBS_MG) = SR%rho_mg_sz
  rho_matrix(OBS_YX,OBS_WL) = SR%rho_wl_x
  rho_matrix(OBS_YX,OBS_VD) = SR%rho_vd_yx
  rho_matrix(OBS_YX,OBS_OR) = SR%rho_or_yx
  rho_matrix(OBS_YX,OBS_LX) = SR%rho_lx_yx
  rho_matrix(OBS_YX,OBS_TX) = SR%rho_tx_yx
  rho_matrix(OBS_YX,OBS_MG) = SR%rho_mg_yx
  rho_matrix(OBS_WL,OBS_VD) = SR%rho_vd_wl
  rho_matrix(OBS_WL,OBS_OR) = SR%rho_or_wl
  rho_matrix(OBS_WL,OBS_LX) = SR%rho_lx_wl
  rho_matrix(OBS_WL,OBS_TX) = SR%rho_tx_wl
  rho_matrix(OBS_WL,OBS_MG) = SR%rho_mg_wl
  rho_matrix(OBS_VD,OBS_OR) = SR%rho_vd_or
  rho_matrix(OBS_VD,OBS_LX) = SR%rho_vd_lx
  rho_matrix(OBS_VD,OBS_TX) = SR%rho_vd_tx
  rho_matrix(OBS_VD,OBS_MG) = SR%rho_vd_mg
  rho_matrix(OBS_OR,OBS_LX) = SR%rho_or_lx
  rho_matrix(OBS_OR,OBS_TX) = SR%rho_or_tx
  rho_matrix(OBS_OR,OBS_MG) = SR%rho_or_mg
  rho_matrix(OBS_LX,OBS_TX) = SR%rho_lx_tx
  rho_matrix(OBS_LX,OBS_MG) = SR%rho_lx_mg
  rho_matrix(OBS_TX,OBS_MG) = SR%rho_tx_mg
  
  rho_matrix = transpose(rho_matrix) + rho_matrix
  do i = 1,MAX_NOBS  
        rho_matrix(i,i) = 1     
  enddo

  ! == Check that the input scaling relation is sensible ==
  input_vec = transfer(SR,input_vec)
  fail = any(input_vec(1:Nszx_SR) .lt. hard_SR_min(1:Nszx_SR) ) .or. &
       any(input_vec(1:Nszx_SR) .gt. hard_SR_max(1:Nszx_SR) ) .or. &
       (this%do_wl .and. ( &
       any(input_vec(iwl_SR:iwl_SR+Nwl_SR-1) .lt. hard_SR_min(iwl_SR:iwl_SR+Nwl_SR-1) ) .or. &
       any(input_vec(iwl_SR:iwl_SR+Nwl_SR-1) .gt. hard_SR_max(iwl_SR:iwl_SR+Nwl_SR-1) ) ) )
  
  if (fail) then 
     CALCULATE_LNLIKE_MC_MATRIX = LogZero
     if(feedback > 0) print*, "Error: hard-coded top-hat prior reached. Please don't rely on this prior!"
     return
  end if
 
 
! == Precompute a bunch of things ==
  delta_sz = (this%parameters%sz_arr(this%parameters%nsz-1) - this%parameters%sz_arr(0)) / (this%parameters%nsz-1)
  delta_z = (this%parameters%z_arr(this%parameters%nz-1) - this%parameters%z_arr(0)) / (this%parameters%nz-1)
  
  delta_lnm =  (this%parameters%lnm_arr(this%parameters%nm-1) - this%parameters%lnm_arr(0)) / (this%parameters%nm-1)

  ez_arr = sqrt( CSM%omm*(1 + this%parameters%z_arr(0:this%parameters%nz-1))**3 + CSM%omv * (1 + this%parameters%z_arr(0:this%parameters%nz-1))**(3 * (1 + CSM%w)) )

  da_arr = ang_diam_dist2(CSM%omm, CSM%omv, csm%h0/1d2, this%parameters%z_arr(0:this%parameters%nz-1),this%parameters%nz, CSM%w, 2d-5)
  z_pivot_index = (this%parameters%z_pivot - this%parameters%z_arr(0)) / delta_z
  
  z_vec(0:this%catalog%n-1) = this%catalog%z_vec(:)
  z_vec(this%catalog%n) = this%parameters%z_pivot
  where(z_vec < 0) z_vec = 1.5
  ez_vec = sqrt( CSM%omm*(1d0 + z_vec(:))**3 + CSM%omv * (1d0 + z_vec(:) )**(3 * (1 + CSM%w)) )
  call dsinterpol(ez_arr,this%parameters%z_arr(0:this%parameters%nz-1),this%parameters%nz, z_vec,ez_vec2, this%catalog%n+1)
  ez_pivot = ez_vec(this%catalog%n)
  call dsinterpol(da_arr,this%parameters%z_arr(0:this%parameters%nz-1),this%parameters%nz, z_vec,da_vec2, this%catalog%n+1)
  da_vec = mkl_linterpol(this%parameters%z_arr(0:this%parameters%nz-1), da_arr,this%parameters%nz,z_vec,this%catalog%n+1)

  da_pivot = da_vec(this%catalog%n)

!= Was PART 2: ln(Yx), but I'm doing first
  call this%yx_calc(csm,SR,ez_vec(0:this%catalog%n-1),da_vec(0:this%catalog%n-1), fail)

  if (fail .ne. 0) then
     CALCULATE_LNLIKE_MC_MATRIX = LogZero
     if (feedback > 0) print*,'yx_calc failed'
     return
  endif

  fid=30
!  call OpenWriteBinaryFile('/home/cr/yx.bin',fid,8_8*this%catalog%n)
!  write(fid,rec=1)this%catalog%x_vec
!  close(fid)
!  print*,this%catalog%x_vec(1:6)
!  call OpenWriteBinaryFile('/home/cr/mf.bin',fid,8_8*this%parameters%nm*this%parameters%nz)
!  write(fid,rec=1)  this%mf%dn
!  close(fid)
!  do i=1,20
!     if (this%catalog%x_vec(i) > 0) print*,'yx',i,this%catalog%x_vec(i)
!  enddo

!  call mpistop()
! == PART 1: Total expected number of clusters ==
  total_clust_lnlike = 0
  total_area = 0
  add_term_lnlike = 0
  do i=1,this%catalog%nfield
     total_area = total_area +  this%catalog%field_area(i)
  enddo

  do i=1,this%catalog%nfield
     thisSR = SR
     thisSR%asz = SR%asz * this%catalog%field_scalefac(i)
     this_nclust = this%compute_ncluster(  thisSR,ez_pivot, ez_arr,da_pivot,da_arr)
     total_clust_lnlike = total_clust_lnlike - this%catalog%field_area(i) * this_nclust
     add_lnlike = -(this%catalog%field_area(i) * this_nclust)/(total_area)
     add_term_lnlike = add_term_lnlike + log(1+add_lnlike*add_lnlike * mean_correl * 0.5)     
  enddo



  total_clust_lnlike = total_clust_lnlike / total_area
  ! == PART 3: Gaussian priors ==
  !SZ ones
  prior_lnlike = 0 - 0.5 * sum( ( (input_vec(1:6) - this%parameters%sz_central_vals)/  this%parameters%sz_prior)**2, &
       (this%parameters%sz_prior.gt. 0))
  !X-ray Yx :
  if (this%do_yx) then
  prior_lnlike = prior_lnlike - 0.5* sum(( (input_vec(7:10) - this%parameters%x_central_vals)/  this%parameters%x_prior)**2, &
       (this%parameters%x_prior.gt. 0))
  endif
  !rho&wl
  if (this%do_wl) then
     if( this%parameters%rhos_prior(1) .gt. 0) &
          prior_lnlike = prior_lnlike - 0.5* ((input_vec(11) - this%parameters%rhos_central_vals(1))/  this%parameters%rhos_prior(1))**2
     prior_lnlike = prior_lnlike - 0.5* sum(( (input_vec(13:18) - this%parameters%wl_central_vals)/  this%parameters%wl_prior)**2, &
          (this%parameters%wl_prior.gt. 0))
     !rest of rho
     prior_lnlike = prior_lnlike - 0.5* sum(( (input_vec(19:20) - this%parameters%rhos_central_vals(2:3))/  this%parameters%rhos_prior(2:3))**2, &
          (this%parameters%rhos_prior(2:3) .gt. 0))
  endif
  !no rho priors added yet after this point
  if (this%do_ysz) then
     prior_lnlike = prior_lnlike - 0.5 * sum(( (input_vec(21:24) - this%parameters%ysz_central_vals)/ this%parameters%ysz_prior)**2, &
          (this%parameters%ysz_prior .gt. 0))
  endif
  !velocity dispersion:
  if (this%do_vd) then
     prior_lnlike = prior_lnlike -0.5 * sum( ( (input_vec(27:31) - this%parameters%vd_central_vals)/ this%parameters%vd_prior)**2,&
          (this%parameters%vd_prior .gt. 0))
  endif
  !Optical Richness:
  if (this%do_OR) then
     prior_lnlike = prior_lnlike -0.5 * sum( ( (input_vec(32:35) - this%parameters%or_central_vals) / this%parameters%or_prior)**2,&
          (this%parameters%or_prior .gt. 0))
  endif
  !X-ray Luminsoity
  if (this%do_Lx) then
     prior_lnlike = prior_lnlike -0.5 * sum( ( (input_vec(36:39) - this%parameters%Lx_central_vals) / this%parameters%lx_prior)**2,&
          (this%parameters%lx_prior .gt. 0))
  endif
  !X-ray Temperature:
  if (this%do_Tx) then
     prior_lnlike = prior_lnlike -0.5 * sum( ( (input_vec(40:43) - this%parameters%tx_central_vals) / this%parameters%tx_prior)**2,&
          (this%parameters%tx_prior .gt. 0))
  endif
  !X-ray Mass gas:
  if (this%do_Mg) then
     prior_lnlike = prior_lnlike -0.5 * sum( ( (input_vec(44:47) - this%parameters%mg_central_vals) / this%parameters%mg_prior)**2,&
          (this%parameters%mg_prior .gt. 0))
  endif
  if (feedback > 1) print*, 'scaling relation prior: ',prior_lnlike
  rhoins_ysz_xi = this%catalog%rhoins_ysz_xi
  print*,rhoins_ysz_xi
  ! == PART 4: Sum of local expectation density at cluster locations == 
  data_lnlike=0
  add_term2_lnlike = 0
#ifndef NOOMPMF
  !$OMP PARALLEL DO DEFAULT(NONE),SCHEDULE(GUIDED),&  
  !$OMP   PRIVATE(iclust,z,fail,failsum,ez,da,z_index,iz1,delta,xi,sig1,sig2,buffer,buffer1,y_matrix,errcode,avxi_samples,zeta_samples,field_scaling_factor,lnM_obs,n_observables,obs_type,zeta_SR,CALCULATE_LNLIKE_MC_MATRIX,dndlnmdz,max_m200,min_m200,int_vec,zeta_wl,zeta_wl_logerr,covar,obs_covar,m200c,m500c,scratch1,scratch2,t2,t1,t0,t_sig,t_mu,t_A,dndlnmdz_samples,like,beta,alpha,data_lnlike,prefactor,pref_int,nzeta,det_obs_cov,ysz_samples,vd_samples,or_samples,lx_samples,tx_samples,mg_samples),&
  !$OMP SHARED(this,ez_vec,da_vec,delta_z,delta_lnm,SR,z_vec,ncoarse,nfine,maxvalue,minvalue,ez_pivot,da_pivot,csm,indelta,outdelta,default,incrit,outcrit,rho_matrix,stream,pref_zeta_boost,pref_zeta,data_lnlike_vec,cov_index,obscov_index,rhoins_ysz_xi,feedback)
#endif 
  do iclust=1,this%catalog%n
     ! == PART 4.1: calculate redshift dependent variables ==
     z = z_vec(iclust-1) ! we're IGNORING redshift err.or.
   
     
     if (z .lt. this%parameters%z_cut) then 
        fail=1
        CALCULATE_LNLIKE_MC_MATRIX = LogZero
        call mpistop('Error: Cluster redshift below allowed minimum.')
     endif

!     tmp1(1) = z
!     call dlinterpol(ez_arr,this%parameters%z_arr(0:this%parameters%nz-1),this%parameters%nz, tmp1,tmp2, 1)
!     ez = tmp2(1)
!     call dlinterpol(da_arr,this%parameters%z_arr(0:this%parameters%nz-1),this%parameters%nz, tmp1,tmp2, 1)
!     da = tmp2(1)
     ez  = ez_vec(iclust-1)
     da = da_vec(iclust-1)
  
     z_index = (z - this%parameters%z_arr(0)) / delta_z
     iz1=floor(z_index)
     delta = z_index - iz1
     if (iz1 .lt. 0 .or. iz1 .ge. this%parameters%nz-1) then
        print*,'OOB redshift ',z,iclust
        call mpistop('Unacceptable cluster redshift')
     endif

     dndlnmdz(:) = (this%mf%dn(:,iz1)*(1-delta) + delta * this%mf%dn(:,iz1+1)) / delta_z / delta_lnm ! mass function dN / dlnM dz at this redshift
     ! == PART 4.2.1: calculate lnM_zeta ==
     xi = this%catalog%sz_vec(iclust)
     if (xi .lt. this%parameters%szthresh) then
         print*, 'Error: Cluster xi below the minimum xi threshold.' 
     endif

     if ( xi .gt. this%parameters%szthresh_max) then
         print*, 'Error: Cluster xi above the maximum xi threshold.'
     endif

     if(this%do_ysz) then
        if(this%catalog%ysz_vec(iclust) .gt. 0 .and. this%catalog%ysz_err_vec(iclust) .ge. 0) then
           if(rhoins_ysz_xi .gt. 0 ) then 
              sig1 = sigma_xi
              sig2 = this%catalog%ysz_err_vec(iclust)
              y_matrix = compute_correlated_errors(sig1,sig2,rhoins_ysz_xi)
              buffer(:) = y_matrix(1,:)
              buffer1(:) = y_matrix(2,:) ! buffer1 is ysz scatter
           else if ( rhoins_ysz_xi .eq. 0) then
              errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, sigma_xi )
              errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer1, zeromean, this%catalog%ysz_err_vec(iclust))
           endif
        endif
     else
        errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, sigma_xi )
     endif
    !buffer is now xi_scatter
     avxi_samples(:) = xi + buffer(:) ! unit scatter to go between xi .and. <xi>
     where(avxi_samples < 0.1) avxi_samples = 0.1 
     ! truncate the distribution at a ridiculously low threshold. This shouldn't matter
     !change from IDL code - using squares
     avxi_samples(:) = avxi_samples(:)*avxi_samples(:)
     
     where(avxi_samples .gt. 4.0 + max_bias) !be sure it's a hair above 2
        zeta_samples = avxi_samples - max_bias
     elsewhere
        zeta_samples = avxi_samples
     endwhere

     
     n_observables = 0
     !this needs a change to catalog structure - I assume I did that at the beginning/load in
     !equivalent to (this%catalog%field_scalefac[where(this%catalog%field_names eq this%catalog%cluster_field[iclust])])[0]
     field_scaling_factor = this%catalog%field_scalefac(this%catalog%field_index(iclust))

     n_observables=n_observables+1
     call vdln(n_samples,zeta_samples,lnM_obs(:,n_observables))
     zeta_SR = log(SR%asz*field_scaling_factor) - SR%bsz * log(this%parameters%mpivot_sz) + SR%csz * log((1 + z)/(1 + this%parameters%z_pivot)) + SR%dsz * log(ez/ez_pivot) + SR%esz * log(da/da_pivot)

 ! start keeping track of mass estimators with an n_observables x n_samples array
  
     call vdln(n_samples,zeta_samples,lnM_obs(:,n_observables))
     lnM_obs(:,n_observables) = (lnM_obs(:,n_observables) - (2*zeta_SR))/ (2*SR%bsz)
 !    print*,iclust,zeta_SR,SR%bsz,lnM_obs(1,n_observables),zeta_samples(1),avxi_samples(1)
!     lnM_obs(:,n_observables) = (log(zeta_samples)/2 - zeta_SR)/SR%bsz !note divide by 2 here is doing sqrt
     obs_type(n_observables) = OBS_SZ  
     ! == PART 4.2.2: calculate lnM_Ysz if Ysz data is available ==
     if (this%do_ysz) then

        if (this%catalog%ysz_vec(iclust) > 0 .and. this%catalog%ysz_err_vec(iclust) >= 0) then     
           buffer = buffer1
           ysz_samples(:) = this%catalog%ysz_vec(iclust) + buffer 
           !where( ysz_samples .le. 0) ysz_samples = 1e-7
           n_observables=n_observables+1
           !lnM_obs(:,n_observables) = log(1e14 * CSM%h0/1d2 * SR%aysz) + SR%bysz * ( (-2. / 3.) * log(ez) + log(ysz_samples(:)/this%parameters%ysz_pivot) )
           lnM_obs(:,n_observables) = log(3e14 * CSM%h0/1d2) + (1/SR%bysz) * (log(1e6 * ysz_samples) - log(SR%aysz) + SR%cysz*log(ez_pivot/ez))
           obs_type(n_observables) = OBS_YSZ
        endif
     endif
     
     ! == PART 4.2.3: calculate lnM_Yx if X-ray data is available ==
     if(this%do_yx) then
        if (this%catalog%logx_err_vec(iclust) > 0) then
           !now buffer Yx scatter
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, log(this%catalog%x_vec(iclust)), this%catalog%logx_err_vec(iclust) )
           
           n_observables=n_observables+1
           lnM_obs(:,n_observables) = SR%bx * (buffer(:)-log(3d0))  + (log(1e14 * SR%ax * (CSM%h0/1d2)**1.5*(CSM%h0/72)**(2.5*SR%bx-1.5)) + SR%cx*log(ez) )
           obs_type(n_observables) = OBS_YX
        endif
     endif
     ! == PART 4.2.4: calculate lnM_wl if weak lensing data is available ==
     if (this%do_wl) then
        zeta_wl = this%catalog%zeta_wl_vec(iclust)
        zeta_wl_logerr = this%catalog%logerr_zeta_wl_vec(iclust)
        if (zeta_wl .gt. 0 .and. zeta_wl_logerr .ge. 0) then 
           !buffer now wl scatter
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, this%catalog%logerr_zeta_wl_vec(iclust)  )
           n_observables=n_observables+1
           lnM_obs(:,n_observables) = log(zeta_wl/SR%awl) + buffer(:)
           obs_type(n_observables) = OBS_WL
        endif
     endif
      
     ! == PART 4.2.5: calculate lnM_vd if velocity dispersion data is available ==
     if (this%do_vd) then
        if( this%catalog%vd_vec(iclust) .gt. 0 .and. this%catalog%vd_err_vec(iclust) .ge. 0) then
           !buffer now velocity disp. scatter        
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean,this%catalog%vd_err_vec(iclust))
           vd_samples(:) = this%catalog%vd_vec(iclust) + buffer
           where ( vd_samples .le. 50) vd_samples = 50 !set any velocity dispersions below 50 equal to 50, should only be less than 0.1% of total  
           n_observables = n_observables + 1
           m200c(:) = (vd_samples(:) / (SR%avd * (ez*CSM%h0/70)**SR%cvd))**SR%bvd*1e15
              
           !use interpolation on vector  with 100 mass values spaced between max(m200c) and min(m200c)
           max_m200 = maxval(m200c)
           min_m200 = minval(m200c)
           int_vec = min_m200 + ((max_m200-min_m200)/99) * (/ (I, I=0,99) /)
           ncoarse = 2e2
           nfine = 1.5e3
           maxvalue = 4
           minvalue = 0.2
           do i=1,100
              int_vec(i) = convert_mass_nfw(int_vec(i),z_vec(iclust),indelta,outdelta,ncoarse,nfine,minvalue,maxvalue,default,incrit,outcrit,csm)
           enddo
         
           m500c = natural_splint_uniform_wscratch(min_m200,max_m200,int_vec,100,m200c,n_samples,scratch1,scratch2)
           
           lnM_obs(:,n_observables) = log(m500c)
           obs_type(n_observables) = OBS_vd
           ! using D_VD = D0_VD + DN_VD/Ngal 
           cov_index(OBS_vd) = (SR%d0vd+SR%dnvd/this%catalog%ngal_vec(iclust))*SR%bvd
           obscov_index(OBS_vd) = (SR%d0vd + SR%dnvd/this%catalog%ngal_vec(iclust))
        endif
     endif
     
     
     ! == PART 4.2.6 calculate lnM_OR if opitcal richness data is available ==
     if(this%do_or) then
        if( this%catalog%OR_vec(iclust) .gt. 0 .and. this%catalog%OR_vec(iclust) .ge. 0) then
           errcode = vdrnggaussian ( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, this%catalog%OR_vec(iclust))
           or_samples(:) = this%catalog%OR_vec(iclust) + buffer 
           n_observables = n_observables + 1
           lnM_obs(:,n_observables) = (log(or_samples(:)) - log(SR%aor) -SR%cor * log(ez / ez_pivot) -SR%bor) / (SR%bor * log( 1/(3e14 * 1/(CSM%h0/72))))
           obs_type(n_observables) = OBS_OR
        endif
     endif
     ! == PART 4.2.7 calculate lnM_Lx if X-ray data available ==
     if ( this%do_Lx) then
        if( this%catalog%Lx_vec(iclust) .gt. 0 .and. this%catalog%Lx_err_vec(iclust) .ge. 0 ) then
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, this%catalog%Lx_err_vec(iclust))
           lx_samples(:) = this%catalog%Lx_vec(iclust) + buffer
           n_observables = n_observables +1
           lnM_obs(:,n_observables) = log(2e14) + (log(lx_samples(:)) - log(SR%alx) - SR%blx*log(ez)) / SR%clx  
           obs_type(n_observables) = OBS_Lx
        endif
     endif
     ! == PART 4.2.8: calculate lnM_TX if X-ray data available ==
     if (this%do_Tx) then
        if(this%catalog%Tx_vec(iclust) .gt. 0 .and. this%catalog%Tx_err_vec(iclust) .ge. 0 ) then
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, this%catalog%Tx_err_vec(iclust))
           tx_samples(:) = this%catalog%Tx_vec(iclust) +buffer
           n_observables = n_observables +1
           lnM_obs(:,n_observables) = log(2e14) + (log(tx_samples(:)) - log(SR%atx) - SR%btx*log(ez)) / SR%ctx
           obs_type(n_observables) = OBS_Tx
        endif
     endif
     ! == PART 4.2.9 calculate lnM_Mg if X-ray data available ==
     if ( this%do_Mg) then
        if( this%catalog%Mg_vec(iclust) .gt. 0 .and. this%catalog%Mg_err_vec(iclust) .ge. 0 ) then
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, this%catalog%Mg_err_vec(iclust))
           mg_samples(:) = this%catalog%Mg_vec(iclust) + buffer
           n_observables = n_observables + 1
           lnM_obs(:,n_observables) = log(2e14) + (log(mg_samples(:)) - log(SR%amg) - SR%bmg*log(ez)) / SR%cmg
           obs_type(n_observables) = OBS_Mg
        endif
     endif
     
     ! == PART 4.3: fill in the covariance matrix .and. compute its inverse ==
     do iobs=1,n_observables
        covar(iobs,iobs)    = cov_index(obs_type(iobs))    * cov_index(obs_type(iobs))
        obs_covar(iobs,iobs) = obscov_index(obs_type(iobs)) * obscov_index(obs_type(iobs))

        do jobs=iobs+1,n_observables

           covar(iobs,jobs)    = cov_index(obs_type(iobs))    * cov_index(obs_type(jobs))   * rho_matrix(obs_type(iobs), obs_type(jobs))
           obs_covar(iobs,jobs) = obscov_index(obs_type(iobs)) * obscov_index(obs_type(jobs))* rho_matrix(obs_type(iobs), obs_type(jobs))
           covar(jobs,iobs)    = covar(iobs,jobs)
           obs_covar(jobs,iobs) = obs_covar(iobs,jobs)
        enddo
     enddo
   
     !don't care about first determinant
     call invert_matrix_in_place(covar(1:n_observables,1:n_observables),n_observables,1d-6,det_obs_cov,fail)
     if (fail .ne. 0) then
           fail=1
           CALCULATE_LNLIKE_MC_MATRIX = LogZero
           if(feedback > 1) print*,'Error: covar: Invalid combination of scatter and correlation parameters.'
           !return
     endif
     failsum = failsum + fail
     call invert_matrix_in_place(obs_covar(1:n_observables,1:n_observables),n_observables,1d-6,det_obs_cov,fail)
     if (fail .ne. 0) then
           fail=1
           CALCULATE_LNLIKE_MC_MATRIX = LogZero
           if(feedback > 1) print*,'Error: obs_covar: Invalid combination of scatter and correlation parameters.'
          ! return
     endif
     failsum = failsum +fail
     ! == PART 4.4: calculate the likelihood term. This part is admittedly opaque so see TdH's derivation ==
     t2 = sum(covar(1:n_observables,1:n_observables))
     t1(:) = 0
     do iobs=1,n_observables
        t1(:) = t1(:) + lnM_obs(:,iobs)*sum(covar(1:n_observables,iobs))
     enddo
     t0(:) = 0
     do iobs=1,n_observables
        do jobs=1,n_observables
           t0(:) = t0(:) + covar(iobs,jobs) * lnM_obs(:,iobs) * lnM_obs(:,jobs)
        enddo
     enddo
     t_sig = 1.0/sqrt(t2)
     t_mu(:) = t1(:)/t2
     t_A(:) = exp(-0.5 * (t0(:) - t1(:)*t1(:)/t2))  * (t_sig /sqrt(det_obs_cov * (2*PI)**(n_observables-1)))
     !buffer now lnM
     errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer, zeromean, t_sig)

     buffer(:) = buffer(:) + t_mu(:)

     dndlnmdz_samples = mkl_linterpol(this%parameters%lnm_arr(0:this%parameters%nm-1),dndlnmdz,this%parameters%nm, buffer,n_samples)

!     call dlinterpol(dndlnmdz, this%parameters%lnm_arr(0:this%parameters%nm-1), this%parameters%nm, buffer, dndlnmdz_samples2,n_samples)
!     print*,'old',dndlnmdz_samples2(1:10)
!     print*,'new',dndlnmdz_samples(1:10)
!     print*,'lnm',lnm_obs(1:5,1)
!     print*,'t2',t2,iclust
!     print*,covar(1:n_observables,1:n_observables)
!     print*,'buffer',t_sig,t_mu(1:10)
!     print*,'b2',buffer(1:10)
!     print*,log(this%parameters%m_cut)   
!     print*,'avxi',avxi_samples(1:10)
!     print*,'ta',t_A(1:10)
!     print*,'samp',dndlnmdz_samples(1:10)
   
 
     
     !now dndlnmdz_samples is being used as scratch
     where(buffer(:) .gt. log(this%parameters%m_cut) .AND. (avxi_samples(:) .lt. 4 .or. avxi_samples(:) .gt. (4. + max_bias)))
        dndlnmdz_samples = dndlnmdz_samples*t_A
     elsewhere
        dndlnmdz_samples = 0
     endwhere
     like = sum(dndlnmdz_samples(:))/n_samples
     if (like == 0) then !should only happen if all points fail above cut
        fail=1
        CALCULATE_LNLIKE_MC_MATRIX = LogZero
        if(feedback > 1) print*,'Error: All monte carlo samples are invalid'
         !return
     endif     
     failsum = failsum + fail
     !   == PART 4.5: Correct the likelihood by the normalization of P(xi|zeta) ==
     nzeta = floor((xi+4.9)/delta_zeta)
     if (nzeta > MAXNZETA) then
        print*,nzeta,MAXNZETA
        call mpistop('nzeta bigger than allowed!')
     endif
     pref_int(1:nzeta) =   exp(-0.5/sigma_xi**2 * (xi-pref_zeta_boost(1:nzeta))**2 ) / pref_zeta(1:nzeta)
     prefactor = sum(pref_int(1:nzeta), &
          this%parameters%mpivot_SZ * (pref_zeta(1:nzeta)/(SR%asz*(ez/ez_pivot)**SR%dsz))**(1./SR%bsz) >  &
          this%parameters%m_cut)
     prefactor = prefactor * (delta_zeta / sqrt(2*PI*sigma_xi**2))
     like = like * prefactor
     ! ==PART 4.6 : add false detection rate ==
     !  we model the false detection rate as N(>xi) = alpha * exp( - beta * (xi-5) )
     if (z == 1.5) then 
        alpha = this%catalog%false_alpha(this%catalog%field_index(iclust))
        beta = this%catalog%false_beta(this%catalog%field_index(iclust))
        !bug fix from Tijmen: 19nov15
        like = like + beta*alpha * exp(-beta*(xi-5))
     endif
     
     if (.not. (like .gt. 0 .and. like .lt. 1e8)) then 
        fail = 1
        CALCULATE_LNLIKE_MC_MATRIX = LogZero
        if(feedback > 1) print*,'Error: Non-finite likelihood',like
        !return
     endif
     failsum = failsum + fail
     data_lnlike_vec(iclust) = log(like) + log(1-like*like*mean_correln*0.5*(2/like -1 ))
     add_term2_vec(iclust) =log(1+ like * like * mean_correln* 0.5) 
  enddo
#ifndef NOOMPMF
  !$OMP END PARALLEL DO                                                                                                                           
#endif
data_lnlike = sum(data_lnlike_vec)
add_term2_lnlike = sum(add_term2_vec)

 !ztest = -0.1 
 ! ncoarse = 200
 ! nfine = 1.2e3
!mtest(1,:) = (/ 7d13, 8d13 ,9d13, 1d14, 2d14,3d14,4d14,5d14,6d14,7d14,8d14,9d14,1d15,2d15,3d15,4d15/)
!mref(1,:) = mtest(1,:) 
!do i=1,21
!ztest = ztest + 0.1
!mref(1+i,:) = mref(i,:)
!     do j = 1,16
!        minvalue = 0.1
!       maxvalue = 5
!        mtest(i,j) = convert_mass_nfw(mref(1,j),ztest,indelta,outdelta,ncoarse,nfine,minvalue,maxvalue,default,incrit,outcrit) / mref(1,j)
! enddo
!     print*,'redshift',ztest
!     print*,mtest(i,:)
!  enddo
  
  
prior_lnlike = - prior_lnlike
data_lnlike = - data_lnlike
total_clust_lnlike = - total_clust_lnlike
add_term_lnlike = -add_term_lnlike
add_term2_lnike = -add_term2_lnlike
  if (feedback > 1) then
     print*, 'total_expected: ', total_clust_lnlike
     print*, 'prior_lnlike: ', prior_lnlike
     print*, 'data_lnlike: ', data_lnlike
     print*,'' 
  endif

  if( failsum .ge. 1 ) then 
     CALCULATE_LNLIKE_MC_MATRIX = LogZero
  else
     CALCULATE_LNLIKE_MC_MATRIX = total_clust_lnlike + prior_lnlike + data_lnlike
  endif
  failsum = 0
 
return
END function CALCULATE_LNLIKE_MC_MATRIX

!this has been checked. agrees with IDL code to numerical
!except due to different input mf%dn
real(mcp) function compute_ncluster(this, SR, ez_pivot, ez_arr,da_pivot,da_arr)
  use MKL_VSL
  use MKL_VSL_TYPE
  implicit none
  type(scalingreln), intent(in) :: SR 
  Class(ClusterLikelihood), intent(in) :: this
  real(mcp), intent(in) :: ez_pivot,da_pivot
  real(mcp), dimension(this%parameters%nz), intent(in) :: ez_arr,da_arr
  integer, parameter :: n_grid = 10000
  real(mcp), dimension(n_grid) :: xi_arr,sf_final,lnm_arr2,xi_arrabove
  real(mcp), dimension(this%parameters%nm) :: sf_lnm,sf_lnm2,lnm_arr
  integer :: i
  real(mcp) kern_sigma_bins
  integer :: nkern
  real(mcp) :: halfnkern,ez, min_index
  real(mcp), dimension(:), allocatable :: ker, zcor
  real(mcp), dimension(0:this%parameters%nm-1, 0:this%parameters%nz-1) ::  dn_selected
  real(mcp), dimension(4) :: range
  integer :: Nfull  
  TYPE(VSL_CONV_TASK)::  task
  TYPE(DF_TASK) taskinterp
  real*8 ::scratch1(n_grid-1),scratch2((n_grid-1)*DF_PP_LINEAR)
  real*8, dimension(0) :: Null
  integer :: dorder(this%parameters%nm)
  real*8 :: datahint(0:3)
  integer start(1),mode
  integer :: status, fail 
  real(mcp) :: tmp,sk
  real(mcp) :: da
  !saved from 1 to next
  integer, save :: firsttime = 1,nuse,firstz
  real(mcp), save, dimension(n_grid) :: zeta_arr,sf,sf_above,sf_below
  real(mcp), save :: delta_lnm
  compute_ncluster = 0
  
  if (firsttime .eq. 1) then 
     
     ! ============ Selection Function Approach =============================
     ! Write the step function in xi and transform it to a selection function in mass at each redshift.
     !  This selection function multiplies the mass function and this grid is integrated. This agrees
     !  with the catalog method at high accuracy and is pretty fast. (0.2s)
     if ( SR%csz .ne. 0 ) call mpistop('Clusters: Implement Csz')
     if ( SR%esz .ne. 0 ) call mpistop('Clusters: Implement Esz')
     
     ! draw out the selection function and tranform it to mass space, then hit the mass function with it and integrate
     ! draw the selection function in xi* space. It looks like a Gaussian centered on the threshold
     if (max_bias <= 0) then
        do i=1,n_grid
           zeta_arr(i) = this%parameters%sz_min + ((this%parameters%sz_max-this%parameters%sz_min)/n_grid) * (i-1)
        enddo
        xi_arr(:) = (zeta_arr(:) - this%parameters%szthresh) / sqrt(2 * sigma_xi * sigma_xi)
        xi_arrabove(:) = (zeta_arr(:) - this%parameters%szthresh_max) / sqrt(2 * sigma_xi * sigma_xi)
        nuse=n_grid
     else

        nuse=0
        do i=1,n_grid
           tmp = this%parameters%sz_min + ((this%parameters%sz_max-this%parameters%sz_min)/n_grid) * (i-1)
           if (tmp <= 2) then
              nuse=nuse+1
              zeta_arr(nuse) = tmp
              xi_arr(nuse)   = tmp
           else 
              if (tmp > sqrt(4+max_bias)) then
                 nuse=nuse+1
                 zeta_arr(nuse) = sqrt(tmp*tmp - max_bias)
                 xi_arr(nuse)   = tmp
              endif
           endif
        enddo
     xi_arrabove(1:nuse)=(xi_arr(1:nuse) -this%parameters%szthresh_max)/ sqrt(2 * sigma_xi * sigma_xi)            
     xi_arr(1:nuse) = (xi_arr(1:nuse) - this%parameters%szthresh) / sqrt(2 * sigma_xi* sigma_xi)
     endif
     
     call vderf(nuse,xi_arr,sf_below)
     call vderf(nuse,xi_arrabove,sf_above)
     sf_below(1:nuse) = (1+sf_below(1:nuse))/2
     sf_above(1:nuse) = 1- (1+sf_above(1:nuse))/2
     sf(1:nuse) = sf_below(1:nuse) - (1-sf_above(1:nuse))
     zeta_arr(1:nuse)  = log(zeta_arr(1:nuse))
     delta_lnm =  (this%parameters%lnm_arr(this%parameters%nm-1) - this%parameters%lnm_arr(0)) / (this%parameters%nm-1)

     do i=this%parameters%nz-1,0,-1
        if (this%parameters%z_arr(i) .lt. this%parameters%z_cut) exit
        firstz=i
     enddo
     firsttime=0
  endif
  ! now convolve with the error in mass space

  kern_sigma_bins = SR%fsz/SR%bsz / delta_lnm 
  halfnkern = floor(4.5 * kern_sigma_bins)+1
  nkern = 2*halfnkern + 1
  Nfull = nkern + nuse -1
  allocate(ker(Nfull),zcor(Nfull))
  do i=-1*halfnkern, halfnkern
     ker(1+i+halfnkern) = exp(-0.5/kern_sigma_bins**2 * (i**2) )
  end do
  sk=sum(ker(1:nkern))
  ker(1:nkern) = ker(1:nkern)/sk
  zcor(halfnkern) =  ker(1)
  do i=2,halfnkern
     zcor(halfnkern+1 - i) = zcor(halfnkern+2 - i) + ker(i)
  end do
  mode = VSL_CONV_MODE_DIRECT;  
  status = vsldconvnewtaskx1d(task, mode, nkern, this%parameters%nm, this%parameters%nm, ker, 1)
  start(1) = halfnkern
  status = vslconvsetstart(task,start) 

  dn_selected(:,0:firstz-1)=0  

!setup interpol
  datahint(0)=nuse
  datahint(1)=DF_NO_APRIORI_INFO
  datahint(2:3)=0
  dorder(:) = 0
  status = dfdnewtask1d(taskinterp, nuse, zeta_arr, DF_NON_UNIFORM_PARTITION, 1, sf, DF_MATRIX_STORAGE_COLS)
  status = dfdeditppspline1d(taskinterp,DF_PP_LINEAR,DF_PP_DEFAULT,&
       DF_NO_BC,&
       Null,DF_IC_1ST_DER,scratch1,&
       scratch2,&
       DF_NO_HINT)
  status = dfdConstruct1D( taskinterp, DF_PP_SPLINE, DF_METHOD_STD )
 
!the loop below  contributes to half the time for one function call with 1 thread,                                                              
!rest of compute_ncluster needs to be parallized for futher improvment, may need slight rewriting.   

#ifndef NOOMPMF
  !$OMP PARALLEL DO DEFAULT(NONE),SCHEDULE(GUIDED),&                                                                                            
  !$OMP PRIVATE(i,lnm_arr,da,ez,sf_final,sf_lnm,status),&            
!$OMP SHARED(this,SR,ez_pivot,da_pivot,zcor,ez_arr,da_arr,dorder,datahint,task,taskinterp,halfnkern,dn_selected,firstz)                       
#endif
  do i=firstz,this%parameters%nz-1 
     ez = ez_arr(i+1)
     da = da_arr(i+1)
     lnm_arr = this%parameters%lnm_arr(0:this%parameters%nm-1)* SR%bsz - (SR%bsz * log(this%parameters%mpivot_sz) - (log(SR%asz) + SR%dsz * log(ez/ez_pivot) + SR%esz * log(da/da_pivot) ))
     status = dfdinterpolate1d(taskinterp,DF_INTERP,DF_METHOD_PP,&
          this%parameters%nm,lnm_arr,DF_SORTED_DATA,1,dorder,datahint,&
          sf_lnm,DF_MATRIX_STORAGE_COLS)

     status = vsldconvexecx1d(task, sf_lnm, 1, sf_final, 1)
     sf_final(1:halfnkern) = sf_final(1:halfnkern) + &
          sf_lnm(1) * zcor(1:halfnkern)
     !upper edge
     sf_final(this%parameters%nm:this%parameters%nm-halfnkern+1:-1) = &
          sf_final(this%parameters%nm:this%parameters%nm-halfnkern+1:-1) +&
          sf_lnm(this%parameters%nm)* zcor(1:halfnkern)
     
     ! remove any numerical artifacts at very low mass
     where(sf_final < 0) &
          sf_final = 0
     where(sf_final > 1) &
          sf_final = 1
     call vdmul(this%parameters%nm,this%mf%dn(:,i), sf_final,dn_selected(:,i))
  enddo
#ifndef NOOMPMF
  !$OMP END PARALLEL DO                                                                                                                         
#endif
  deallocate(ker,zcor)
  status = vslconvdeletetask(task)
  status = dfdeletetask(taskinterp)

  min_index = (log(this%parameters%m_cut)-this%parameters%lnm_arr(0))/delta_lnm
  range(3) = 0
  range(4) = this%parameters%nz-1
  range(1) = min_index
  range(2) = this%parameters%nm-1

  compute_ncluster = square_int_alt(dn_selected,this%parameters%nm, &
       this%parameters%nz, range,fail)
  return  
end function compute_ncluster


subroutine yx_calc(this,csm, SR, ez_vec,da_vec, fail)
  USE, INTRINSIC :: IEEE_ARITHMETIC
  implicit none
  type(scalingreln), intent(in) :: SR 
  type(cosmoprm),intent(in) :: csm
  Class(ClusterLikelihood) :: this
  integer, intent(out) :: fail
  real(mcp), intent(in), dimension(this%catalog%n) :: da_vec, ez_vec
  real(mcp), dimension(this%catalog%n) :: yx_vec
  integer :: i,j,maxind,maxind2
  real(mcp):: r500,z,ez,yxold,Mg, kT,Yx, rhoc,angrad,r500ref
  real(mcp) :: da, da_ref,dafac, dafac2p5
  real(mcp), parameter :: yxtol = 1e10
  real(mcp), parameter :: G = 4.3d-3
  real(mcp) m500prefactor,r500prefactor
  real(mcp), dimension(1) :: t1,t2
    
!  print*,'yx inputs',CSM%h0
!  print*,'ez', ez_vec(1:this%catalog%n:10)
!  print*,'da',da_vec(1:this%catalog%n:10)
!  print*,'rtx',this%catalog%r_tx(1:this%catalog%n2:20,1)
!  print*,'txr',this%catalog%txr_vec(1:this%catalog%n2:20,1)
  fail = 0
  yx_vec(:)=0d0

  !cluster loop
  do i=1,this%catalog%n
     da_ref = this%catalog%da_vec(i)
     r500=1000.0
     !check for no xray
     if (da_ref .le. 0.0 .or. &
          maxval(this%catalog%mgr_vec(:,i)) .le. 0. .or. &
          maxval(this%catalog%txr_vec(:,i)) .le. 0. ) then
        yx_vec(i)=-1e14
        cycle !goto next cluster
     endif
     
!code to cut to nelements here
     maxind=this%catalog%n2
     do j=this%catalog%n2,1,-1
        if (this%catalog%mgr_vec(j,i) .gt. 0 .and. this%catalog%r_mg(j,i) .gt. 0 ) then 
           maxind = j
           exit ! break
        endif
     enddo
     maxind2=this%catalog%n2
     do j=this%catalog%n2,1,-1
        if (this%catalog%txr_vec(j,i) .gt. 0 .and. this%catalog%r_tx(j,i) .gt. 0 ) then 
           maxind2 = j
           exit ! break
        endif
     enddo
          
     z = this%catalog%z_vec(i)
     da = da_vec(i)
     ez = ez_vec(i)
     yxold=0
     dafac = da/da_ref
     dafac2p5=dafac**2.5
     rhoc=3.*(csm%H0*ez)**2 / (8.*Pi*G) * 1d6

     m500prefactor = (SR%ax*1d14*((csm%H0/100.0)**0.5*(csm%H0/72)**(2.5*SR%bx-1.5))* ez**(SR%cx)) 
     r500prefactor = 1000. * (3./rhoc/500./4./Pi*m500prefactor)**(1./3.)      
    ! print*,i,z,'da',da,'ez',ez,rhoc,dafac,dafac2p5

     do j=0,99 
        r500ref=r500/dafac
        angrad=r500/da/1000./Pi*180.*3600.
        !define Mg/kT here WITH INTERPOL
        t1(1)=r500ref
        t2 = mkl_linterpol_sorted(this%catalog%r_mg(1:maxind,i),this%catalog%mgr_vec(1:maxind,i),maxind,t1,1)
        Mg=t2(1)
        t1(1)=angrad
        t2 = mkl_linterpol_sorted(this%catalog%r_tx(1:maxind2,i),this%catalog%txr_vec(1:maxind2,i),maxind2,t1,1)
        kT=t2(1)
 !       print*,'interp at',r500ref
 !       print*,'interp range1:',j,i,maxind,this%catalog%mgr_vec(1,i),this%catalog%mgr_vec(maxind,i),this%catalog%r_mg(1,i),this%catalog%r_mg(maxind,i)
 !       print*,'interp at',angrad
 !       print*,'interp range2:',j,i,maxind2,this%catalog%txr_vec(1,i),this%catalog%txr_vec(maxind2,i),this%catalog%r_tx(1,i),this%catalog%r_tx(maxind2,i)
        
        Mg=Mg*dafac2p5

        Yx=Mg*kT
!        if (i == 1) then 
!           print*,i,j,z,da,ez,r500ref,angrad,Mg,kT,Yx
!        endif

 !       print*,'mg/kt',Mg,kT,angrad,r500ref
        r500 = r500prefactor * ( Yx/(3d14))**(SR%bx/3.)
        if (abs(Yx-yxold) .lt. yxtol .and. j .gt. 9)  exit
        yxold=Yx
     enddo
     if (.not. (Yx > 0)) then
        print*,'yx calc fail:',i,Yx
        fail = 1
        return
     endif

     yx_vec(i)=Yx
  enddo
  
  THIS%CATALOG%x_vec(1:this%catalog%n)=yx_vec(1:this%catalog%n)/1d14
  return

end subroutine yx_calc



function ratio_resid(ratio, conc, delta_ratio,nvec)
  integer, intent(in) :: nvec
  real(mcp), intent(in) :: delta_ratio, conc
  real(mcp), dimension(nvec), intent(in) :: ratio  
  integer :: i
  real(mcp), dimension(nvec) :: ratio_resid
  
  ratio_resid = ratio**3*delta_ratio -(log(1 + conc*ratio) - conc*ratio/(1+conc*ratio)) / (log(1+conc) - conc/(1+conc))
end function ratio_resid

!=================================================================================
!
!  largely based on convert_mass_nfw.pro written by Tdh (spt_analysis/source/convert_mass_nfw.pro)
!  Converts between the given mass definition and any other mass definition
!  
!  Key differences are we finding a coarse minimum and then finding a better approx
!  by finding minimum over a small range surrounding coarse minimum using a much smaller step size
!  set ncoarse = 1000, nfine = 3000 to recover accuracy of idl code, but two orders lower amount of function calls (much faster)
!  keep ncoarse set above 200.
!  Inputs:
!        mass - Input cluster mass, which is to be converted
!        z    - Cluster redshift
!        indelta - overdensity of input mass
!        outdelta - overdensity of output mass
!        ncoarse - specifies step size to find coarse minimum of ratio_resid 
!        nfine - specifies step size to find minimum of ratio_resid
!        default - 1 specifies to use Duffy et. al. 2008 concentration parameters for non relaxed clusters
!        minvalue - specifies lower bound on range of values to find min of ratio_resid (keep below 0.4)
!        maxvalue - specifies uper bound on range of values to find min of ratio_resid (keep above 2)
!        incrit - set = 1 if input mass is with respect to crit density (yes for our scaling relations)
!        incrit - set =1 if output mass is desired to be with  respect to crit density (yes for our scaling relations)
!  Ouputs:
!       cluster mass in terms of the specified overdensity
!==================================================================================
function convert_mass_nfw(mass,z,indelta,outdelta,ncoarse,nfine,minvalue,maxvalue,default,incrit,outcrit,csm)
  implicit none
  type(cosmoprm) :: csm
  real(mcp) :: convert_mass_nfw
  integer, intent(in) :: ncoarse,nfine
  real(mcp), intent(in) :: mass, indelta, outdelta, z
  integer, intent(in) :: default, incrit, outcrit
  real(mcp) :: A, B, C
  real(mcp),intent(in) :: minvalue, maxvalue
  real(mcp) :: OmegaMz,OmegaM, Delta_200c, Delta_out
  real(mcp) :: r_ratio, m_ratio, m200c,m_out, conc_0, conc_1, conc
  integer :: i, n_iter = 2 
  real(mcp), dimension(ncoarse) :: ratvec_coarse, residvec_coarse,rangecoarse
  real(mcp), dimension(nfine) :: ratvec_fine, residvec_fine,rangefine
  real(mcp) :: newmin,newmax
! using c200(rho_crit) = A (M200(Msun h^-1) / 2e12 Msun h^-1)^B (1+z)^C
! if default = 1 : using Duffy et al 2008 parameters for non relaxed clusters
  if( default .eq. 1) then
     A = 5.71
     B = -0.084
     C= -0.47
  endif
  if( default .eq. 2) then ! Duffy 2008 relaxed clusters conc parameters
     A = 6.71
     B = -0.091
     C = -0.44
  endif
  !OmegaM = 0.264
  OmegaM = CSM%omm
  OmegaMz = OmegaM * (1 + z)**3 / (OmegaM * (1 +z)**3 - OmegaM +1)
  !convert input mass to M200c using almost-right concentration
  conc_0 = A*(mass/2d12)**B*(1 + z)**C
  Delta_200c = indelta/200
  if (incrit .eq. 0) then 
     Delta_200c = OmegaMz*Delta_200c
  endif
  
rangecoarse= (/(I, I =0, ncoarse-1, 1)/)
ratvec_coarse = minvalue + rangecoarse/(ncoarse-1)*(maxvalue-minvalue)
residvec_coarse = ratio_resid(ratvec_coarse, conc_0, Delta_200c,ncoarse)
r_ratio = ratvec_coarse(MINLOC(residvec_coarse**2,1))

if( r_ratio .gt. maxvalue .or. r_ratio .le. minvalue .and. feedback .gt. 1) then
   print*, ' min or max exceeded' , r_ratio
endif

if( nfine .gt. ncoarse) then 
   newmin = r_ratio - 1.5*(maxvalue -minvalue)/ncoarse
   newmax = r_ratio + 1.5*(maxvalue -minvalue)/ncoarse
   rangefine = (/(I, I = 0, nfine-1, 1)/)
   ratvec_fine = newmin + rangefine/(nfine-1)*(newmax - newmin)
   residvec_fine = ratio_resid(ratvec_fine, conc_0,Delta_200c,nfine)
   r_ratio = ratvec_fine(MINLOC(residvec_fine**2,1))

   if( ratvec_fine(MINLOC(residvec_fine**2,1)) .gt. newmax .or. ratvec_fine(MINLOC(residvec_fine**2,1)) .le. newmin .and. feedback .gt. 1) then
      print*,'min or max exceeded : ratvec_fine =' ,ratvec_fine(MINLOC(residvec_fine**2,1)), newmax, newmin, maxval(ratvec_fine)
   endif

endif

  m_ratio = Delta_200c*r_ratio**3
  m200c = mass / m_ratio
  !convert input to M200c using the updated concentraiton:
  do i = 1, n_iter
     conc_1 = A*(m200c/2d12)**B*(1+z)**C
     
     ratvec_coarse = minvalue + rangecoarse/(ncoarse-1)*(maxvalue-minvalue)
     residvec_coarse = ratio_resid(ratvec_coarse, conc_1, Delta_200c,ncoarse)
     r_ratio = ratvec_coarse(MINLOC(residvec_coarse**2,1))

     if( r_ratio .gt. maxvalue .or. r_ratio .le. minvalue) then
        print*, ' min or max exceeded' , r_ratio
     endif

     if( nfine  .gt. ncoarse) then
        newmin = r_ratio - 1.5*(maxvalue -minvalue)/ncoarse
        newmax = r_ratio + 1.5*(maxvalue -minvalue)/ncoarse
        ratvec_fine = newmin + rangefine/(nfine-1)*(newmax - newmin)
        residvec_fine = ratio_resid(ratvec_fine, conc_1,Delta_200c,nfine)
        r_ratio = ratvec_fine(MINLOC(residvec_fine**2,1))

        if( ratvec_fine(MINLOC(residvec_fine**2,1)) .gt. newmax .or. ratvec_fine(MINLOC(residvec_fine**2,1)) .le. newmin) then
           print*,'min or max exceeded : ratvec_fine =' ,ratvec_fine(MINLOC(residvec_fine**2,1)), newmax, newmin, maxval(ratvec_fine)
        endif

     endif
     m_ratio = Delta_200c*r_ratio**3
     m200c = mass / m_ratio
  enddo
  conc = A*(m200c / 2d12)**B*(1+z)**C


  !Now use the concentration and M200c to convert to requested output mass definition
  Delta_out = outdelta / 200
  if (outcrit .eq. 0) then 
     Delta_out = OmegaMz*Delta_out
  endif
  
  ratvec_coarse = minvalue + rangecoarse/(ncoarse-1)*(maxvalue-minvalue)
  residvec_coarse = ratio_resid(ratvec_coarse, conc, Delta_out,ncoarse)
  r_ratio = ratvec_coarse(MINLOC(residvec_coarse**2,1))
  
  if( r_ratio .gt. maxvalue .or. r_ratio .le. minvalue) then
     print*, ' min or max exceeded' , r_ratio
  endif

  if( nfine .gt. ncoarse) then
     newmin = r_ratio - 1.5*(maxvalue -minvalue)/ncoarse
     newmax = r_ratio + 1.5*(maxvalue -minvalue)/ncoarse
     ratvec_fine = newmin + rangefine/(nfine-1)*(newmax - newmin)
     residvec_fine = ratio_resid(ratvec_fine, conc,Delta_out,nfine)
     r_ratio = ratvec_fine(MINLOC(residvec_fine**2,1))

     if( ratvec_fine(MINLOC(residvec_fine**2,1)) .gt. newmax .or. ratvec_fine(MINLOC(residvec_fine**2,1)) .le. newmin) then
        print*,'min or max exceeded : ratvec_fine =' ,ratvec_fine(MINLOC(residvec_fine**2,1)),newmax,newmin,maxval(ratvec_fine)
     endif
 
  endif
  m_ratio = Delta_out*r_ratio**3
  m_out = m200c * m_ratio
  convert_mass_nfw = m_out
end function convert_mass_nfw

function compute_correlated_errors(sig1,sig2,rho)
  implicit none
  real(mcp), intent(in) :: sig1, sig2, rho
  real(mcp), dimension(2,n_samples) :: compute_correlated_errors
  real(mcp), dimension(2,2) :: u_matrix
  real(mcp), dimension(2,n_samples) :: x_matrix, y_matrix
  real(mcp), dimension(n_samples) :: buffer1, buffer2
  real(mcp) :: norm1, norm2, cov12, cova, covar1, covar2
           cov12 = rho*sig1*sig2
           cova =  sqrt(-2*sig1**2*sig2**2 + sig1**4+sig2**4+4*(cov12**2))
           covar1 = 0.5*(-cova+sig1**2+sig2**2)
           covar2 = 0.5*(cova+sig1**2+sig2**2)
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer1, zeromean, sqrt(covar1))
           errcode = vdrnggaussian( VSL_RNG_METHOD_GAUSSIAN_ICDF, stream, n_samples, buffer2, zeromean, sqrt(covar2))
           x_matrix(1,:) = buffer2(:)
           x_matrix(2,:) = buffer1(:)
! fill in u_matrix with orthonormal eigenvectors as columns
           u_matrix(1,2) = -(-sig1**2+sig2**2 + cova) / (2*cov12)
           u_matrix(2,1) = 1
           u_matrix(2,2) = 1
           u_matrix(1,1) = (sig1**2 - sig2**2 + cova) / (2*cov12)
           norm1 = sqrt(u_matrix(1,1)**2 + u_matrix(2,1)**2)
           norm2 = sqrt(u_matrix(1,2)**2 + u_matrix(2,2)**2)
           u_matrix(:,1)= u_matrix(:,1)/norm1
           u_matrix(:,2)= u_matrix(:,2)/norm2
! transform back to ysz and xi basis
           y_matrix = MATMUL(u_matrix,x_matrix)
           compute_correlated_errors = y_matrix
end function compute_correlated_errors

subroutine invert_matrix_in_place(matrix,n,mineval,determinant,fail)
  implicit none
  integer, intent(in) :: n
  real(mcp), intent(in) :: mineval
  integer, intent(out) :: fail
  real(mcp), intent(out) :: determinant
  real(mcp), dimension(n,n) :: matrix,evecs,lambda
  real(mcp), dimension(n) :: evals
  integer, dimension(2*n) :: isuppz
  integer :: lwork,liwork
  real(mcp), dimension(n*n+26*n) :: work
  integer, dimension(10*n)  :: iwork
  integer neval,i,info
  lwork = n*n+26*n
  liwork=10*n
  fail = 0
  if (mcp .ne. 8) call mpistop('Cluster.f90: assumed mcp is double')
  call dsyevr('V','A','U',n,matrix,n,0d0,0d0,0,0,1d-8,neval,evals, evecs,n,isuppz,work,lwork,iwork,liwork,info)

  if (info .ne. 0) then 
     fail=1
     return
  endif
  if (any(evals(1:neval) .lt. mineval) .or. neval .ne. n) then
     fail=1
     return
  endif
  determinant=product(evals(1:neval))
  lambda(:,:) = 0
  do i=1,n
     lambda(i,i) = 1./evals(i)
  enddo
  call dgemm('N','T',n,n,n,1d0,lambda,n,evecs,n,0d0,matrix,n)
  call dgemm('N','N',n,n,n,1d0,evecs,n,matrix,n,0d0,lambda,n)
  matrix=lambda
  return
end subroutine invert_matrix_in_place

subroutine OpenReadBinaryStreamFile(aname,aunit)
  character(LEN=*), intent(IN) :: aname
  integer, intent(in) :: aunit
  open(unit=aunit,file=aname,form='unformatted',access='stream', err=500)
  return
500 call MpiStop('File not found: '//trim(aname))
end subroutine OpenReadBinaryStreamFile

subroutine OpenWriteBinaryFile(aname,aunit,record_length)
  character(LEN=*), intent(IN) :: aname
  integer, intent(in) :: aunit
  integer*8,intent(in) :: record_length
  open(unit=aunit,file=aname,form='unformatted',status='replace',access='direct',recl=record_length, err=500)
  return
  
500 call MpiStop('File not able to be written to: '//trim(aname))
end subroutine OpenWriteBinaryFile


subroutine OpenReadBinaryFile(aname,aunit,record_length)
  character(LEN=*), intent(IN) :: aname
  integer, intent(in) :: aunit
  integer*8,intent(in) :: record_length
  open(unit=aunit,file=aname,form='unformatted',access='direct',action='read',recl=record_length, err=500)
  return
  
500 call MpiStop('File not found: '//trim(aname))
end subroutine OpenReadBinaryFile


end module Cluster
