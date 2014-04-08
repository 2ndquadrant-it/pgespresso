%global pgmajorversion 93
%global pginstdir /usr/pgsql-9.3
%global sname pgespresso

Summary:	Optional Extension for Barman, Backup and Recovery Manager for PostgreSQL
Name:		%{sname}%{pgmajorversion}
Version:	1.0
Release:	1%{?dist}
License:	BSD
Group:		Applications/Databases
Source0:        %{sname}-%{version}.tar.gz
URL:		https://github.com/2ndquadrant-it/%{sname}
BuildRequires:	postgresql%{pgmajorversion}-devel
Requires:	postgresql%{pgmajorversion}-server
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Vendor:         2ndQuadrant Italia (Devise.IT S.r.l.) <info@2ndquadrant.it>

%description
pgespresso is an extension that adds functions and views to be used by Barman,
the disaster recovery tool written by 2ndQuadrant and released as open source.

%prep
%setup -q -n %{sname}-%{version}

%build
make PG_CONFIG=%{pginstdir}/bin/pg_config %{?_smp_mflags}

%install
rm -rf %{buildroot}
make PG_CONFIG=%{pginstdir}/bin/pg_config %{?_smp_mflags} install DESTDIR=%{buildroot}

%clean
rm -rf %{buildroot}

%post -p /sbin/ldconfig 
%postun -p /sbin/ldconfig 

%files
%defattr(644,root,root,755)
%doc COPYING README.asciidoc
%{pginstdir}/lib/%{sname}.so
%{pginstdir}/share/extension/%{sname}*.sql
%{pginstdir}/share/extension/%{sname}.control

%changelog
* Mon Apr 7 2013 - Marco Nenciarini <marco.nenciarini@2ndquadrant.it> 1.0-1
- Initial packaging.
