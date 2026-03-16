# Stop generation of debug rpms
%global debug_package %{nil}

Name:           {{ package_name }}
Version:        {{ package_initial_version }}
Release:        1%{?dist}
Summary:        Filter for improving compression of typed binary data.

License:        LicenseRef-Callaway-MIT
URL:            https://github.com/NSLS2/{{ package_name }}-rpm
Source0:        {{ package_url }}/archive/refs/tags/%{version}.tar.gz

BuildRequires:  
Requires:       
Recommends:     

BuildArch:      x86_64

# Prevent rpmbuild from smart-generating dependencies list
#AutoReq:        no

%description
{{ package_description }}

{% if pacakge_include_devel %}
%package devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_includedirisa} = %{version}-%{release}

%description devel
This package contains the header files, unversioned shared libraries
(e.g., .so files), and other resources needed for developing applications
that use %{name}.

{% endif %}
%prep
%autosetup

%build
# Build {{ package_name }}

%install
# Install {{ package_name }}

%files
%license LICENSE
# Include executables and versioned shared libraries here.

{% if package_include_devel %}
%files devel
%license LICENSE
# Include header files and non-versioned shared libraries here.
{% endif %}


%changelog
* {{ now.strftime('%b %d %Y') }} {{ author }} <{{ author_email }}> - {{ package_initial_version }}-1
- Initial release of {{ package_name }} as an RPM.