from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User,Profile,Listing,ListingPhoto,Application,ApplicationEvent
@admin.register(User)
class AccountAdmin(UserAdmin):
    ordering=['email']
    list_display=['email','name','role','email_verified','is_staff']
    search_fields=['email','name']
    fieldsets=((None,{'fields':('email','password')}),('Profile',{'fields':('name','role','email_verified')}),
               ('Access',{'fields':('is_active','is_staff','is_superuser','groups','user_permissions')}),)
    add_fieldsets=((None,{'classes':('wide',),'fields':('email','name','role','password1','password2')}),)
admin.site.register(Profile)
# Business invariants must not be bypassed by editing application records in admin.
class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self,request): return False
    def has_change_permission(self,request,obj=None): return False
    def has_delete_permission(self,request,obj=None): return False
for model in (Listing,ListingPhoto,Application,ApplicationEvent): admin.site.register(model,ReadOnlyAdmin)
