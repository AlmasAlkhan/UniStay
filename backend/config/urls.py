from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include,path
from rest_framework.routers import DefaultRouter
from drf_spectacular.views import SpectacularAPIView,SpectacularSwaggerView
from core import views
router=DefaultRouter()
router.register('listings',views.ListingViewSet,basename='listing')
router.register('applications',views.ApplicationViewSet,basename='application')
urlpatterns=[
    path('admin/',admin.site.urls),path('health/',views.health),
    path('api/v1/auth/register/',views.RegisterView.as_view()),
    path('api/v1/auth/login/',views.LoginView.as_view()),
    path('api/v1/auth/logout/',views.LogoutView.as_view()),
    path('api/v1/auth/verify-email/',views.VerifyView.as_view()),
    path('api/v1/auth/resend-verification/',views.EmailRequestView.as_view()),
    path('api/v1/auth/password-reset/',views.ResetRequestView.as_view()),
    path('api/v1/auth/password-reset/confirm/',views.ResetConfirmView.as_view()),
    path('api/v1/me/',views.MeView.as_view()),path('api/v1/me/profile/',views.ProfileView.as_view()),
    path('api/v1/photos/<int:pk>/',views.PhotoDeleteView.as_view()),
    path('api/v1/',include(router.urls)),
    path('api/schema/',SpectacularAPIView.as_view(),name='schema'),
    path('api/docs/',SpectacularSwaggerView.as_view(url_name='schema'),name='swagger-ui'),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL,document_root=settings.MEDIA_ROOT)
